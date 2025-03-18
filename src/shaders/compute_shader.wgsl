struct Particle {
    position: vec2<f32>,
    velocity: vec2<f32>,
};

struct QuadNode {
    min_bound: vec2<f32>,
    max_bound: vec2<f32>,
    children: vec4<u32>, // 4 child indices, or -1u for a leaf
    particle_start: u32, // Index into the particle buffer
    particle_count: u32, // Number of particles in this node
};

@group(0) @binding(0) var<storage, read_write> particles: array<Particle>;
@group(0) @binding(1) var<storage, read_write> quadtree: array<QuadNode>;

// Constants
const MAX_PARTICLES_PER_LEAF: u32 = 10u;
const MAX_TREE_DEPTH: u32 = 6u;
const ROOT_NODE_INDEX: u32 = 0u;
const PERCEPTION_RADIUS: f32 = 0.1;
const MAX_SPEED: f32 = 0.02;
const MAX_FORCE: f32 = 0.005;
const BOUNDARY_LIMIT: f32 = 1.0;

@compute @workgroup_size(256)
fn build_quadtree(@builtin(global_invocation_id) id: vec3<u32>) {
    let index: u32 = id.x;
    if index >= arrayLength(&particles) { return; }

    let p = particles[index];

    // Start at the root and find the correct leaf node
    var node_index: u32 = ROOT_NODE_INDEX;

    loop {
        let node = quadtree[node_index];

        // If this is a leaf node
        if node.children.x == 0xffffffffu { // -1u means no children
            // If there's space, insert particle
            if node.particle_count < MAX_PARTICLES_PER_LEAF {
                quadtree[node_index].particle_count += 1u;
                return;
            }

            // Otherwise, split the node
            split_node(node_index);
        }

        // Find correct child node
        node_index = find_child(node_index, p.position);
    }
}

// Splitting a quadtree node into 4 children
fn split_node(node_index: u32) {
    let node = quadtree[node_index];

    let mid = (node.min_bound + node.max_bound) * 0.5;
    let min_bound = node.min_bound;
    let max_bound = node.max_bound;

    let child_base_index: u32 = node_index * 4u + 1u;

    quadtree[child_base_index + 0u] = QuadNode(min_bound, mid, vec4<u32>(0xffffffffu), 0u, 0u);
    quadtree[child_base_index + 1u] = QuadNode(vec2<f32>(mid.x, min_bound.y), vec2<f32>(max_bound.x, mid.y), vec4<u32>(0xffffffffu), 0u, 0u);
    quadtree[child_base_index + 2u] = QuadNode(vec2<f32>(min_bound.x, mid.y), vec2<f32>(mid.x, max_bound.y), vec4<u32>(0xffffffffu), 0u, 0u);
    quadtree[child_base_index + 3u] = QuadNode(mid, max_bound, vec4<u32>(0xffffffffu), 0u, 0u);

    quadtree[node_index].children = vec4<u32>(child_base_index, child_base_index + 1u, child_base_index + 2u, child_base_index + 3u);
}

// Finding the child index for a given position
fn find_child(node_index: u32, pos: vec2<f32>) -> u32 {
    let node = quadtree[node_index];
    let mid = (node.min_bound + node.max_bound) * 0.5;

    if pos.x < mid.x {
        if pos.y < mid.y { return node.children[0u]; } else { return node.children[2u]; }
    } else {
        if pos.y < mid.y { return node.children[1u]; } else { return node.children[3u]; }
    }
}

// Query neighbors using stack-based traversal (avoiding recursion)
fn query_neighbors(node_index: u32, pos: vec2<f32>, radius: f32, out_neighbors: ptr<function, array<u32, 10>>) -> u32 {
    var stack: array<u32, 64>; // Simulated stack
    var stack_size: u32 = 0u;
    var total: u32 = 0u;

    stack[stack_size] = node_index;
    stack_size += 1u;

    while stack_size > 0u {
        stack_size -= 1u;
        let current_index = stack[stack_size];
        let node = quadtree[current_index];

        // Skip nodes that do not intersect the query radius
        if !overlaps(node.min_bound, node.max_bound, pos, radius) {
            continue;
        }

        // If leaf node, check particles
        if node.children.x == 0xffffffffu {
            var i: u32 = node.particle_start;
            while i < (node.particle_start + node.particle_count) {
                let p = particles[i];
                if length(p.position - pos) < radius {
                    (*out_neighbors)[total] = i;  // ✅ Correctly dereference the pointer
                    total += 1u;
                    if total >= 10u { return total; } // Max neighbors reached
                }
                i += 1u;
            }
        } else {
            // Push child nodes onto stack
            var i: u32 = 0u;
            while i < 4u {
                stack[stack_size] = node.children[i];
                stack_size += 1u;
                i += 1u;
            }
        }
    }

    return total;
}

// Check if a region overlaps a node
fn overlaps(min_bound: vec2<f32>, max_bound: vec2<f32>, pos: vec2<f32>, radius: f32) -> bool {
    let closest = clamp(pos, min_bound, max_bound);
    return length(closest - pos) < radius;
}

// Compute shader for Boid Simulation using QuadTree
@compute @workgroup_size(256)
fn simulate_boids(@builtin(global_invocation_id) id: vec3<u32>) {
    let index: u32 = id.x;
    if index >= arrayLength(&particles) { return; }

    var p = particles[index];

    var alignment: vec2<f32> = vec2<f32>(0.0, 0.0);
    var cohesion: vec2<f32> = vec2<f32>(0.0, 0.0);
    var separation: vec2<f32> = vec2<f32>(0.0, 0.0);
    var total: u32 = 0u;
    var neighbors: array<u32, 10>;

    let num_neighbors = query_neighbors(ROOT_NODE_INDEX, p.position, PERCEPTION_RADIUS, &neighbors);

    if num_neighbors > 0u {
        var i: u32 = 0u;
        while i < num_neighbors {
            let neighbor = particles[neighbors[i]];
            alignment += neighbor.velocity;
            cohesion += neighbor.position;
            separation += (p.position - neighbor.position) / max(length(p.position - neighbor.position), 0.0001);
            total += 1u;
            i += 1u;
        }

        let total_f32: f32 = f32(total);
        alignment /= total_f32;
        cohesion /= total_f32;
        separation /= total_f32;

        p.velocity += normalize(alignment) * MAX_SPEED;
        p.velocity += normalize(cohesion - p.position) * MAX_SPEED;
        p.velocity += normalize(separation) * MAX_SPEED;
    }

    // Apply boundary conditions
    if abs(p.position.x) > BOUNDARY_LIMIT { p.velocity.x *= -1.0; }
    if abs(p.position.y) > BOUNDARY_LIMIT { p.velocity.y *= -1.0; }

    p.position += p.velocity;
    particles[index] = p;
}
