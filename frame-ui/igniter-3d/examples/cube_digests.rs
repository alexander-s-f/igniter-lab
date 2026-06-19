use igniter_3d::Cube3dRuntime;
fn main() {
    let mut rt = Cube3dRuntime::new();
    let first = rt.render_digest();
    for _ in 0..30 { rt.tick(); }
    println!("native first = {}", first);
    println!("native last  = {}", rt.render_digest());
}
