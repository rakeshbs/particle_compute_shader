use nannou::prelude::*;
use nannou::wgpu::{self, BufferUsages, ComputePassDescriptor, ShaderStages};
use std::mem;

const PARTICLE_COUNT: u32 = 5_0000;

struct Model {
    simulate_pipeline: wgpu::ComputePipeline,
    render_pipeline: wgpu::RenderPipeline,
    particle_buffer: wgpu::Buffer,
    bind_group: wgpu::BindGroup,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct Particle {
    position: [f32; 2],
    velocity: [f32; 2],
}

fn model(app: &App) -> Model {
    let window_id = app.new_window().size(1024, 768).view(view).build().unwrap();
    let window = app.window(window_id).unwrap();
    let device = window.device();

    // Load shaders
    let compute_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("Compute Shader"),
        source: wgpu::ShaderSource::Wgsl(include_str!("./shaders/compute_shader.wgsl").into()),
    });
    let vertex_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("Vertex Shader"),
        source: wgpu::ShaderSource::Wgsl(include_str!("./shaders/vertex_shader.wgsl").into()),
    });

    let fragment_shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("Fragment Shader"),
        source: wgpu::ShaderSource::Wgsl(include_str!("./shaders/fragment_shader.wgsl").into()),
    });

    // Create buffer for particles
    let particles = (0..PARTICLE_COUNT)
        .map(|_| Particle {
            position: [random_range(-1.0, 1.0), random_range(-1.0, 1.0)],
            velocity: [random_range(-0.001, 0.001), random_range(-0.001, 0.001)],
        })
        .collect::<Vec<_>>();

    let particle_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("Particle Buffer"),
        contents: bytemuck::cast_slice(&particles),
        usage: BufferUsages::STORAGE | BufferUsages::VERTEX | BufferUsages::COPY_DST,
    });

    // Create bind group
    let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("Bind Group Layout"),
        entries: &[wgpu::BindGroupLayoutEntry {
            binding: 0,
            visibility: ShaderStages::COMPUTE,
            ty: wgpu::BindingType::Buffer {
                ty: wgpu::BufferBindingType::Storage { read_only: false },
                has_dynamic_offset: false,
                min_binding_size: None,
            },
            count: None,
        }],
    });

    let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("Bind Group"),
        layout: &bind_group_layout,
        entries: &[wgpu::BindGroupEntry {
            binding: 0,
            resource: particle_buffer.as_entire_binding(),
        }],
    });

    // Compute pipeline
    let simulate_pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("Simulate Pipeline Layout"),
        bind_group_layouts: &[&bind_group_layout],
        push_constant_ranges: &[],
    });

    let simulate_pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("Simulate Pipeline"),
        layout: Some(&simulate_pipeline_layout),
        module: &compute_shader,
        entry_point: "simulate_boids",
    });

    // Render pipeline
    let render_pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("Render Pipeline Layout"),
        bind_group_layouts: &[],
        push_constant_ranges: &[],
    });

    // Make sure your vertex buffer layout correctly maps the struct fields
    let vertex_buffer_layout = wgpu::VertexBufferLayout {
        array_stride: mem::size_of::<Particle>() as wgpu::BufferAddress,
        step_mode: wgpu::VertexStepMode::Instance,
        attributes: &[
            // Position
            wgpu::VertexAttribute {
                offset: 0,
                shader_location: 0,
                format: wgpu::VertexFormat::Float32x2,
            },
            // Velocity
            wgpu::VertexAttribute {
                offset: 8, // 2 * 4 bytes for the position
                shader_location: 1,
                format: wgpu::VertexFormat::Float32x2,
            },
        ],
    };

    let render_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some("Render Pipeline"),
        layout: Some(&render_pipeline_layout),
        vertex: wgpu::VertexState {
            module: &vertex_shader,
            entry_point: "vs_main",
            buffers: &[vertex_buffer_layout],
        },
        fragment: Some(wgpu::FragmentState {
            module: &fragment_shader,
            entry_point: "fs_main",
            targets: &[Some(wgpu::ColorTargetState {
                format: wgpu::TextureFormat::Rgba16Float,
                blend: Some(wgpu::BlendState::REPLACE),
                write_mask: wgpu::ColorWrites::ALL,
            })],
        }),
        primitive: wgpu::PrimitiveState {
            topology: wgpu::PrimitiveTopology::TriangleList,
            strip_index_format: None,
            front_face: wgpu::FrontFace::Ccw,
            cull_mode: None,
            polygon_mode: wgpu::PolygonMode::Fill,
            unclipped_depth: false,
            conservative: false,
        },
        depth_stencil: None,
        multisample: wgpu::MultisampleState {
            count: 4,
            mask: !0,
            alpha_to_coverage_enabled: false,
        },
        multiview: None,
    });

    Model {
        simulate_pipeline,
        render_pipeline,
        particle_buffer,
        bind_group,
    }
}

fn update(app: &App, model: &mut Model, _update: Update) {
    let window = app.main_window();
    let queue = window.queue();

    let mut encoder = window
        .device()
        .create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("Compute Encoder"),
        });
    {
        let mut compute_pass = encoder.begin_compute_pass(&ComputePassDescriptor {
            label: Some("Compute Pass"),
        });
        compute_pass.set_pipeline(&model.simulate_pipeline);
        compute_pass.set_bind_group(0, &model.bind_group, &[]);
        let workgroups_x = (PARTICLE_COUNT as f32 / 256.0).ceil() as u32; // e.g., 63
                                                                          //
        compute_pass.dispatch_workgroups(workgroups_x, 1, 1);
    }
    queue.submit(Some(encoder.finish()));
}

fn view(app: &App, model: &Model, frame: Frame) {
    let device = frame.device_queue_pair().device();
    let queue = frame.device_queue_pair().queue();

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("Render Encoder"),
    });

    let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
        label: Some("Render Pass"),
        color_attachments: &[Some(wgpu::RenderPassColorAttachment {
            view: frame.texture_view(),
            resolve_target: None,
            ops: wgpu::Operations {
                load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                store: true,
            },
        })],
        depth_stencil_attachment: None,
    });

    // In the view function, change the draw call to:
    render_pass.set_pipeline(&model.render_pipeline);
    render_pass.set_vertex_buffer(0, model.particle_buffer.slice(..));
    render_pass.draw(0..3, 0..PARTICLE_COUNT); // Draw 3 vertices per instance, PARTICLE_COUNT instances

    drop(render_pass);
    queue.submit(Some(encoder.finish()));
}

fn main() {
    nannou::app(model).update(update).run();
}
