//! A WebSocket load client for the sweep. `--mode=echo` keeps every
//! connection in a closed loop of one message and its echo, and reports
//! the round trips per second after a warm-up with their latency.
//! `--mode=idle` opens the connections and leaves them quiet, and reports
//! what they added to the server's resident memory. Given the server's pid
//! on Linux, echo also reports the cores the server used while measured.
//! Each run prints one line of JSON.
//!
//!   relic_baseline_ws_load --mode=echo --url=ws://127.0.0.1:8301/ \
//!       --connections=64 --size=64 --seconds=10 --warmup=3 --threads=8
//!   relic_baseline_ws_load --mode=idle --url=ws://127.0.0.1:8301/ \
//!       --connections=10000 --seconds=5 --pid=1234

use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use futures_util::{SinkExt, StreamExt};
use hdrhistogram::Histogram;
use tokio::net::TcpStream;
use tokio::sync::Semaphore;
use tokio_tungstenite::tungstenite::protocol::WebSocketConfig;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

type Socket = WebSocketStream<MaybeTlsStream<TcpStream>>;

const WARMUP: u8 = 0;
const MEASURE: u8 = 1;
const STOP: u8 = 2;
const TIMEOUT: Duration = Duration::from_secs(10);

struct Args {
    mode: String,
    url: String,
    connections: usize,
    seconds: f64,
    warmup: f64,
    size: usize,
    binary: bool,
    threads: usize,
    pid: Option<u32>,
}

fn parse_args() -> Args {
    let mut args = Args {
        mode: "echo".into(),
        url: "ws://127.0.0.1:8301/".into(),
        connections: 64,
        seconds: 10.0,
        warmup: 3.0,
        size: 64,
        binary: false,
        threads: 4,
        pid: None,
    };
    for arg in std::env::args().skip(1) {
        let (key, value) = arg.split_once('=').unwrap_or((arg.as_str(), ""));
        match key {
            "--mode" => args.mode = value.into(),
            "--url" => args.url = value.into(),
            "--connections" => args.connections = value.parse().expect("--connections"),
            "--seconds" => args.seconds = value.parse().expect("--seconds"),
            "--warmup" => args.warmup = value.parse().expect("--warmup"),
            "--size" => args.size = value.parse().expect("--size"),
            "--binary" => args.binary = true,
            "--threads" => args.threads = value.parse().expect("--threads"),
            "--pid" => args.pid = value.parse().ok(),
            _ => panic!("unknown argument {arg}"),
        }
    }
    args
}

/// Raises the soft limit on open files to the hard one, for the idle run's
/// thousands of sockets.
fn raise_file_limit() {
    unsafe {
        let mut limit = libc::rlimit { rlim_cur: 0, rlim_max: 0 };
        if libc::getrlimit(libc::RLIMIT_NOFILE, &mut limit) == 0 {
            limit.rlim_cur = limit.rlim_max;
            libc::setrlimit(libc::RLIMIT_NOFILE, &limit);
        }
    }
}

/// The user and system time of process `pid` in seconds, from /proc.
fn cpu_seconds(pid: Option<u32>) -> Option<f64> {
    let stat = std::fs::read_to_string(format!("/proc/{}/stat", pid?)).ok()?;
    // Fields after the command name, which can hold spaces: state is the
    // first, utime the twelfth and stime the thirteenth.
    let fields: Vec<&str> = stat.rsplit_once(')')?.1.split_whitespace().collect();
    let ticks: f64 = fields.get(11)?.parse::<f64>().ok()? + fields.get(12)?.parse::<f64>().ok()?;
    let per_second = unsafe { libc::sysconf(libc::_SC_CLK_TCK) } as f64;
    Some(ticks / per_second)
}

/// The resident memory of process `pid` in KiB, from /proc.
fn rss_kib(pid: Option<u32>) -> Option<u64> {
    let status = std::fs::read_to_string(format!("/proc/{}/status", pid?)).ok()?;
    let line = status.lines().find(|l| l.starts_with("VmRSS:"))?;
    line.split_whitespace().nth(1)?.parse().ok()
}

fn json_opt<T: std::fmt::Display>(value: Option<T>) -> String {
    value.map_or("null".into(), |v| v.to_string())
}

/// Opens `count` connections, at most 256 handshakes at a time, each
/// reading into 4 KiB rather than tungstenite's default 128 KiB. Failed
/// ones are left out.
async fn connect_all(url: &str, count: usize) -> Vec<Socket> {
    let gate = Arc::new(Semaphore::new(256));
    let handles: Vec<_> = (0..count)
        .map(|_| {
            let gate = gate.clone();
            let url = url.to_string();
            tokio::spawn(async move {
                let _permit = gate.acquire_owned().await.ok()?;
                let mut config = WebSocketConfig::default();
                config.read_buffer_size = 4096;
                let connect = tokio_tungstenite::connect_async_with_config(url, Some(config), true);
                match tokio::time::timeout(TIMEOUT, connect).await {
                    Ok(Ok((socket, _))) => Some(socket),
                    _ => None,
                }
            })
        })
        .collect();
    let mut sockets = Vec::with_capacity(count);
    for handle in handles {
        if let Ok(Some(socket)) = handle.await {
            sockets.push(socket);
        }
    }
    sockets
}

fn message(size: usize, binary: bool) -> Message {
    if binary {
        Message::binary(vec![0u8; size])
    } else {
        Message::text("x".repeat(size))
    }
}

/// Sends `message` and waits for its echo. False on an error, a close or
/// no answer within the timeout.
async fn round_trip(socket: &mut Socket, message: &Message) -> bool {
    if socket.send(message.clone()).await.is_err() {
        return false;
    }
    loop {
        match tokio::time::timeout(TIMEOUT, socket.next()).await {
            Ok(Some(Ok(Message::Text(_) | Message::Binary(_)))) => return true,
            Ok(Some(Ok(Message::Ping(_) | Message::Pong(_) | Message::Frame(_)))) => continue,
            _ => return false,
        }
    }
}

async fn echo(args: &Args) {
    let sockets = connect_all(&args.url, args.connections).await;
    let opened = sockets.len();
    let phase = Arc::new(AtomicU8::new(WARMUP));
    let message = message(args.size, args.binary);
    let drivers: Vec<_> = sockets
        .into_iter()
        .map(|mut socket| {
            let phase = phase.clone();
            let message = message.clone();
            tokio::spawn(async move {
                let mut latencies = Histogram::<u64>::new_with_bounds(1, 60_000_000, 3).unwrap();
                let mut failed = false;
                loop {
                    let current = phase.load(Ordering::Relaxed);
                    if current == STOP {
                        break;
                    }
                    let sent = Instant::now();
                    if !round_trip(&mut socket, &message).await {
                        failed = true;
                        break;
                    }
                    if current == MEASURE && phase.load(Ordering::Relaxed) == MEASURE {
                        let _ = latencies.record(sent.elapsed().as_micros().max(1) as u64);
                    }
                }
                let _ = socket.close(None).await;
                (latencies, failed)
            })
        })
        .collect();
    tokio::time::sleep(Duration::from_secs_f64(args.warmup)).await;
    let cpu_start = cpu_seconds(args.pid);
    let start = Instant::now();
    phase.store(MEASURE, Ordering::Relaxed);
    tokio::time::sleep(Duration::from_secs_f64(args.seconds)).await;
    phase.store(STOP, Ordering::Relaxed);
    let elapsed = start.elapsed().as_secs_f64();
    let cpu_end = cpu_seconds(args.pid);
    let rss = rss_kib(args.pid);
    let mut all = Histogram::<u64>::new_with_bounds(1, 60_000_000, 3).unwrap();
    let mut errors = 0;
    for driver in drivers {
        if let Ok((latencies, failed)) = driver.await {
            all.add(&latencies).unwrap();
            errors += failed as usize;
        }
    }
    let cores = match (cpu_start, cpu_end) {
        (Some(a), Some(b)) => Some(format!("{:.3}", (b - a) / elapsed)),
        _ => None,
    };
    println!(
        "{{\"mode\":\"echo\",\"connections\":{},\"opened\":{},\"size\":{},\"binary\":{},\
         \"seconds\":{:.3},\"round_trips\":{},\"rate\":{:.1},\"p50_us\":{},\"p90_us\":{},\
         \"p99_us\":{},\"max_us\":{},\"server_cores\":{},\"server_rss_kib\":{},\"errors\":{}}}",
        args.connections,
        opened,
        args.size,
        args.binary,
        elapsed,
        all.len(),
        all.len() as f64 / elapsed,
        all.value_at_quantile(0.5),
        all.value_at_quantile(0.9),
        all.value_at_quantile(0.99),
        all.max(),
        json_opt(cores),
        json_opt(rss),
        errors,
    );
}

async fn idle(args: &Args) {
    let before = rss_kib(args.pid);
    let started = Instant::now();
    let mut sockets = connect_all(&args.url, args.connections).await;
    let connect_seconds = started.elapsed().as_secs_f64();
    tokio::time::sleep(Duration::from_secs_f64(args.seconds)).await;
    let after = rss_kib(args.pid);
    // Every connection must still answer, or the memory figure counts
    // connections the server has dropped.
    let message = message(args.size, args.binary);
    let checks: Vec<_> = sockets
        .drain(..)
        .map(|mut socket| {
            let message = message.clone();
            tokio::spawn(async move {
                let alive = round_trip(&mut socket, &message).await;
                let _ = socket.close(None).await;
                alive
            })
        })
        .collect();
    let mut opened = 0;
    let mut alive = 0;
    for check in checks {
        opened += 1;
        alive += check.await.unwrap_or(false) as usize;
    }
    let per_connection = match (before, after) {
        (Some(b), Some(a)) if opened > 0 => {
            Some(format!("{:.0}", (a as f64 - b as f64) * 1024.0 / opened as f64))
        }
        _ => None,
    };
    println!(
        "{{\"mode\":\"idle\",\"connections\":{},\"opened\":{},\"alive\":{},\
         \"connect_seconds\":{:.3},\"rss_before_kib\":{},\"rss_after_kib\":{},\
         \"bytes_per_connection\":{}}}",
        args.connections,
        opened,
        alive,
        connect_seconds,
        json_opt(before),
        json_opt(after),
        json_opt(per_connection),
    );
}

fn main() {
    let args = parse_args();
    raise_file_limit();
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(args.threads.max(1))
        .enable_all()
        .build()
        .expect("runtime");
    runtime.block_on(async {
        match args.mode.as_str() {
            "echo" => echo(&args).await,
            "idle" => idle(&args).await,
            other => panic!("unknown mode {other}"),
        }
    });
}
