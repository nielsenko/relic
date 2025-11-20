use std::convert::Infallible;
use std::net::SocketAddr;
use hyper::{Body, Request, Response, Server};
use hyper::service::{make_service_fn, service_fn};
use tokio::runtime::Runtime;

async fn handle(_: Request<Body>) -> Result<Response<Body>, Infallible> {
    Ok(Response::new("Hello, World!".into()))
}

#[no_mangle]
pub extern "C" fn start_server() {
    std::thread::spawn(|| {
        let rt = Runtime::new().unwrap();
        rt.block_on(async {
            let addr = SocketAddr::from(([127, 0, 0, 1], 3000));

            let make_svc = make_service_fn(|_conn| async {
                Ok::<_, Infallible>(service_fn(handle))
            });

            let server = Server::bind(&addr).serve(make_svc);

            if let Err(e) = server.await {
                eprintln!("server error: {}", e);
            }
        });
    });
}
