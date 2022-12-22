pub fn Vec2(comptime T: type) type {
    return struct {
        const Self = @This();
        pub fn zero() Self {
            return .{
                .x = 0,
                .y = 0,
            };
        }

        x: T,
        y: T,

        pub fn eql(vec_a: Self, vec_b: Self) bool {
            return (vec_a.x == vec_b.x and
                vec_a.y == vec_b.y);
        }

        pub fn sub(vec_a: Self, vec_b: Self) Self {
            return .{
                .x = vec_a.x - vec_b.x,
                .y = vec_a.y - vec_b.y,
            };
        }
    };
}

pub fn Vec3(comptime T: type) type {
    return struct {
        x: T,
        y: T,
        z: T,
    };
}

pub fn Vec4(comptime T: type) type {
    return struct {
        x: T,
        y: T,
        z: T,
        w: T,
    };
}

pub fn hexToColorVector(hex: u24) Vec3(f32) {
    var r = (1.0 / 255.0) * @intToFloat(f32, hex >> 16);
    var g = (1.0 / 255.0) * @intToFloat(f32, (hex >> 8) & 0xFF);
    var b = (1.0 / 255.0) * @intToFloat(f32, hex & 0xFF);
    return .{ .x = r, .y = g, .z = b };
}

pub fn createOrthoMatrix(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) [4 * 4]f32 {
    // matrix goes TOP TO BOTTOM, LEFT TO RIGHT
    var matrix = createIdentityMatirx();
    matrix[0] = 2 / (right - left);
    matrix[5] = 2 / (top - bottom);
    matrix[10] = -2 / (far - near);
    matrix[12] = -((right + left) / (right - left));
    matrix[13] = -((top + bottom) / (top - bottom));
    matrix[14] = -((far + near) / (far - near));
    return matrix;
}

pub fn translateMatrix(matrix: [4 * 4]f32, vector: Vec3(f32)) [4 * 4]f32 {
    var new_matrix = matrix;

    // 4th column
    new_matrix[12] = vector.x + matrix[12];
    new_matrix[13] = vector.y + matrix[13];
    new_matrix[14] = vector.z + matrix[14];

    return new_matrix;
}

pub fn translateVector(matrix: [4 * 4]f32, vector: Vec4(f32)) Vec4(f32) {
    return .{
        // 4th column
        .x = vector.x + matrix[12],
        .y = vector.y + matrix[13],
        .z = vector.z + matrix[14],
        .w = matrix[15],
    };
}

pub fn createIdentityMatirx() [4 * 4]f32 {
    // matrix goes TOP TO BOTTOM, LEFT TO RIGHT
    // zig fmt: off
    return [_]f32 {
        1,0,0,0,
        0,1,0,0,
        0,0,1,0,
        0,0,0,1,
    };
    // zig fmt: on
}
