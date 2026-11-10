//! A WebSocket server on tokio-tungstenite that sends every message back,
//! the native floor for the sweep's WebSocket rows. A second number after
//! the port is the worker thread count, one by default so it compares with
//! one isolate, and one worker runs on the current thread with no pool.
//! Each connection reads into 4 KiB instead of tungstenite's default 128
//! KiB, so an idle connection's memory is the connection's, not a buffer's.
//! With a certificate chain and a key after the worker count it serves wss
//! through rustls, as the hyper baseline serves HTTPS.
//!
//!   cargo run --release --bin relic_baseline_ws_echo -- 8301
//!   cargo run --release --bin relic_baseline_ws_echo -- 8304 4
//!   cargo run --release --bin relic_baseline_ws_echo -- 8351 1 \
//!       ../../../relic_native/test/certs/localhost_cert.pem \
//!       ../../../relic_native/test/certs/localhost_key.pem

use std::sync::Arc;

use futures_util::{SinkExt, StreamExt};
use rustls_pki_types::pem::PemObject;
use rustls_pki_types::{CertificateDer, PrivateKeyDer};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::TcpListener;
use tokio_rustls::TlsAcceptor;
use tokio_tungstenite::tungstenite::protocol::WebSocketConfig;
use tokio_tungstenite::tungstenite::Message;

async fn echo<S: AsyncRead + AsyncWrite + Unpin>(stream: S) {
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

fn tls_acceptor(cert_path: &str, key_path: &str) -> TlsAcceptor {
    let certs = CertificateDer::pem_file_iter(cert_path)
        .and_then(|certs| certs.collect::<Result<Vec<_>, _>>())
        .expect("certificate chain");
    let key = PrivateKeyDer::from_pem_file(key_path).expect("key");
    let config = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certs, key)
        .expect("certificate and key");
    TlsAcceptor::from(Arc::new(config))
}

async fn serve(port: u16, acceptor: Option<TlsAcceptor>) {
    let listener = TcpListener::bind(("127.0.0.1", port)).await.expect("bind");
    loop {
        let Ok((stream, _)) = listener.accept().await else {
            continue;
        };
        let _ = stream.set_nodelay(true);
        match acceptor.clone() {
            None => drop(tokio::spawn(echo(stream))),
            Some(acceptor) => drop(tokio::spawn(async move {
                if let Ok(tls) = acceptor.accept(stream).await {
                    echo(tls).await;
                }
            })),
        }
    }
}

fn main() {
    let mut args = std::env::args().skip(1);
    let port: u16 = args.next().and_then(|a| a.parse().ok()).unwrap_or(8301);
    let threads: usize = args.next().and_then(|a| a.parse().ok()).unwrap_or(1);
    let acceptor = args.next().map(|cert| {
        let key = args.next().expect("key path missing");
        tls_acceptor(&cert, &key)
    });
    let runtime = if threads <= 1 {
        tokio::runtime::Builder::new_current_thread().enable_all().build()
    } else {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(threads)
            .enable_all()
            .build()
    }
    .expect("runtime");
    runtime.block_on(serve(port, acceptor));
}
