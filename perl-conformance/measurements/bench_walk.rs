// Publication-walk bench for share-on-spawn: build a graph with the node and
// edge counts measured from a real stash walk (Mojolicious + Moose + DateTime
// loaded), lay the nodes out in randomized order so pointer chasing pays
// realistic cache misses, then time one DFS that flips each header's SHARED
// bit and switches its refcount mode.
use std::env;
use std::time::Instant;

struct Node {
    header: u64,
    edges: Vec<u32>,
}

const SHARED: u64 = 1;

fn main() {
    let args: Vec<String> = env::args().collect();
    let n: usize = args.get(1).and_then(|s| s.parse().ok()).unwrap_or(188_338);
    let e: usize = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(232_346);

    // Deterministic xorshift so runs are comparable.
    let mut seed: u64 = 0x9e3779b97f4a7c15;
    let mut rng = move || {
        seed ^= seed << 13;
        seed ^= seed >> 7;
        seed ^= seed << 17;
        seed
    };

    // Random spanning tree guarantees reachability; the remaining edges are
    // random. Node identifiers are then shuffled so graph order does not
    // match allocation order.
    let mut perm: Vec<u32> = (0..n as u32).collect();
    for i in (1..n).rev() {
        let j = (rng() % (i as u64 + 1)) as usize;
        perm.swap(i, j);
    }
    let mut nodes: Vec<Node> = (0..n)
        .map(|_| Node { header: 0, edges: Vec::new() })
        .collect();
    for i in 1..n {
        let parent = (rng() % i as u64) as usize;
        nodes[perm[parent] as usize].edges.push(perm[i]);
    }
    let mut extra = e.saturating_sub(n - 1);
    while extra > 0 {
        let a = (rng() % n as u64) as usize;
        let b = perm[(rng() % n as u64) as usize];
        nodes[a].edges.push(b);
        extra -= 1;
    }

    let root = perm[0] as usize;
    let mut stack: Vec<u32> = Vec::with_capacity(1024);
    let t0 = Instant::now();
    stack.push(root as u32);
    nodes[root].header |= SHARED;
    let mut visited: u64 = 1;
    while let Some(ix) = stack.pop() {
        let node = &nodes[ix as usize];
        let edge_count = node.edges.len();
        for k in 0..edge_count {
            let t = nodes[ix as usize].edges[k];
            let h = &mut nodes[t as usize].header;
            if *h & SHARED == 0 {
                *h |= SHARED;
                visited += 1;
                stack.push(t);
            }
        }
    }
    let dt = t0.elapsed().as_secs_f64();
    println!(
        "n={} e={} visited={} walk_ms={:.2} ns_per_node={:.1}",
        n, e, visited, dt * 1e3, dt / visited as f64 * 1e9
    );
}
