#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
    float4 color [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    out.color = in.color;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                             texture2d<float> fontAtlas [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float4 texColor = fontAtlas.sample(textureSampler, in.texCoord);
    
    // Use the texture alpha as a mask for the character
    float alpha = texColor.a;
    
    // Blend the character color with the background
    float4 finalColor = in.color * alpha;
    
    return finalColor;
}
