//! A WebSocket server on tokio-tungstenite that sends every message back,
//! the native floor for the sweep's WebSocket rows. A second number after
//! the port is the worker thread count, one by default so it compares with
//! one isolate, and one worker runs on the current thread with no pool.
//! Each connection reads into 4 KiB instead of tungstenite's default 128
//! KiB, so an idle connection's memory is the connection's, not a buffer's.
//!
//!   cargo run --release --bin relic_baseline_ws_echo -- 8301
//!   cargo run --release --bin relic_baseline_ws_echo -- 8304 4

use futures_util::{SinkExt, StreamExt};
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::tungstenite::protocol::WebSocketConfig;
use tokio_tungstenite::tungstenite::Message;

async fn echo(stream: TcpStream) {
    let _ = stream.set_nodelay(true);
    let mut config = WebSocketConfig::default();
    config.read_buffer_size = 4096;
    let Ok(ws) = tokio_tungstenite::accept_async_with_config(stream, Some(config)).await else {
        return;
    };
    let (mut tx, mut rx) = ws.split();
    while let Some(Ok(message)) = rx.next().await {
        match message {
            Message::Text(_) | Message::Binary(_) => {
                if tx.send(message).await.is_err() {
                    return;
                }
            }
            Message::Close(_) => return,
            _ => {}
        }
    }
}

async fn serve(port: u16) {
    let listener = TcpListener::bind(("127.0.0.1", port)).await.expect("bind");
    loop {
        if let Ok((stream, _)) = listener.accept().await {
            tokio::spawn(echo(stream));
        }
    }
}

fn main() {
    let mut args = std::env::args().skip(1);
    let port: u16 = args.next().and_then(|a| a.parse().ok()).unwrap_or(8301);
    let threads: usize = args.next().and_then(|a| a.parse().ok()).unwrap_or(1);
    let runtime = if threads <= 1 {
        tokio::runtime::Builder::new_current_thread().enable_all().build()
    } else {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(threads)
            .enable_all()
            .build()
    }
    .expect("runtime");
    runtime.block_on(serve(port));
}
