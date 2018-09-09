#import "iTermTextShaderCommon.h"
#import <metal_math>

// Slow path: taken for all underlined code paths and all solid background code paths (because they aren't used
// and I don't want to spend time testing dead code right now).
vertex iTermTextVertexFunctionOutput
iTermTextVertexShader(uint vertexID [[ vertex_id ]],
                      constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                      constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                      constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                      device iTermTextPIU *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                      unsigned int iid [[instance_id]]) {
    iTermTextVertexFunctionOutput out;

    // pixelSpacePosition is in pixels
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy + perInstanceUniforms[iid].offset.xy + offset[0];
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;
    out.backgroundTextureCoordinate = pixelSpacePosition / viewportSize;
    out.backgroundTextureCoordinate.y = 1 - out.backgroundTextureCoordinate.y;
    out.textureOffset = perInstanceUniforms[iid].textureOffset;
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate + perInstanceUniforms[iid].textureOffset;
    out.textColor = perInstanceUniforms[iid].textColor;
    out.backgroundColor = perInstanceUniforms[iid].backgroundColor;
    out.colorModelIndex = perInstanceUniforms[iid].colorModelIndex;
    out.viewportSize = viewportSize;

    out.cellOffset = perInstanceUniforms[iid].offset.xy + offset[0];
    out.underlineStyle = perInstanceUniforms[iid].underlineStyle;
    out.underlineColor = static_cast<half4>(perInstanceUniforms[iid].underlineColor);

    return out;
}

vertex iTermTextVertexFunctionOutputEmoji
iTermTextVertexShaderEmoji(uint vertexID [[ vertex_id ]],
                           constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                           constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                           constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                           device iTermTextPIU *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                           unsigned int iid [[instance_id]]) {
    iTermTextVertexFunctionOutputEmoji out;

    // pixelSpacePosition is in pixels
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy + perInstanceUniforms[iid].offset.xy + offset[0];
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    out.textureCoordinate = vertexArray[vertexID].textureCoordinate + perInstanceUniforms[iid].textureOffset;

    return out;
}

// Not emoji, not underlined, not using the solid background color optimization, not macOS 10.14
vertex iTermTextVertexFunctionOutputBlending
iTermTextVertexShaderBlending(uint vertexID [[ vertex_id ]],
                              constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                              constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                              constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                              device iTermTextPIU *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                              unsigned int iid [[instance_id]]) {
    iTermTextVertexFunctionOutputBlending out;

    // pixelSpacePosition is in pixels
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy + perInstanceUniforms[iid].offset.xy + offset[0];
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    out.textureCoordinate = vertexArray[vertexID].textureCoordinate + perInstanceUniforms[iid].textureOffset;
    out.backgroundTextureCoordinate = pixelSpacePosition / viewportSize;
    out.backgroundTextureCoordinate.y = 1 - out.backgroundTextureCoordinate.y;
    out.textColor = perInstanceUniforms[iid].textColor;

    return out;
}


// Not emoji, not underlined, macOS 10.14 (no subpixel AA support)
vertex iTermTextVertexFunctionOutputMonochrome
iTermTextVertexShaderMonochrome(uint vertexID [[ vertex_id ]],
                                constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                                constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                                constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                                device iTermTextPIU *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                                unsigned int iid [[instance_id]]) {
    iTermTextVertexFunctionOutputMonochrome out;

    // pixelSpacePosition is in pixels
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy + perInstanceUniforms[iid].offset.xy + offset[0];
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    out.textureCoordinate = vertexArray[vertexID].textureCoordinate + perInstanceUniforms[iid].textureOffset;
    out.textColor = static_cast<half4>(perInstanceUniforms[iid].textColor);

    return out;
}

// The underlining fragment shaders are separate from the non-underlining ones
// because of an apparent compiler bug. See issue 6779.

#pragma mark - Fragment Shaders

// "Blending" is slower but can deal with any combination of foreground/background
// color components. It's used when there's a background image, a badge,
// broadcast image stripes, or anything else nontrivial behind the text.

// This function is shared by blending and monochrome because Emoji without underline doesn't take the background color into account.
fragment half4
iTermTextFragmentShaderWithBlendingEmoji(iTermTextVertexFunctionOutputEmoji in [[stage_in]],
                                         texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]],
                                         texture2d<half> drawable [[ texture(iTermTextureIndexBackground) ]],
                                         texture2d<half> colorModels [[ texture(iTermTextureIndexSubpixelModels) ]],
                                         constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    return texture.sample(textureSampler, in.textureCoordinate);
}

fragment half4
iTermTextFragmentShaderWithBlending(iTermTextVertexFunctionOutputBlending in [[stage_in]],
                                    texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]],
                                    texture2d<half> drawable [[ texture(iTermTextureIndexBackground) ]],
                                    texture2d<half> colorModels [[ texture(iTermTextureIndexSubpixelModels) ]],
                                    constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    half4 bwColor = texture.sample(textureSampler, in.textureCoordinate);
    const float4 backgroundColor = static_cast<float4>(drawable.sample(textureSampler, in.backgroundTextureCoordinate));

    // Not emoji, not underlined.
    if (bwColor.x == 1 && bwColor.y == 1 && bwColor.z == 1) {
        discard_fragment();
    }

    return RemapColor(in.textColor * 17.0, backgroundColor, static_cast<float4>(bwColor), colorModels);
}

fragment half4
iTermTextFragmentShaderWithBlendingUnderlinedEmoji(iTermTextVertexFunctionOutput in [[stage_in]],
                                                   texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]],
                                                   texture2d<half> drawable [[ texture(iTermTextureIndexBackground) ]],
                                                   texture2d<half> colorModels [[ texture(iTermTextureIndexSubpixelModels) ]],
                                                   constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    half4 bwColor = texture.sample(textureSampler, in.textureCoordinate);

    // Underlined emoji code path
    const half underlineWeight = ComputeWeightOfUnderlineRegular(in.underlineStyle,
                                                                 in.clipSpacePosition.xy,
                                                                 in.viewportSize,
                                                                 in.cellOffset,
                                                                 dimensions->underlineOffset,
                                                                 dimensions->underlineThickness,
                                                                 dimensions->textureSize,
                                                                 in.textureOffset,
                                                                 in.textureCoordinate,
                                                                 dimensions->cellSize,
                                                                 texture,
                                                                 textureSampler,
                                                                 dimensions->scale);
    return mix(bwColor,
               in.underlineColor,
               underlineWeight);
}

fragment half4
iTermTextFragmentShaderWithBlendingUnderlined(iTermTextVertexFunctionOutput in [[stage_in]],
                                              texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]],
                                              texture2d<half> drawable [[ texture(iTermTextureIndexBackground) ]],
                                              texture2d<half> colorModels [[ texture(iTermTextureIndexSubpixelModels) ]],
                                              constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    half4 bwColor = texture.sample(textureSampler, in.textureCoordinate);
    const float4 backgroundColor = static_cast<float4>(drawable.sample(textureSampler, in.backgroundTextureCoordinate));

    // Underlined not emoji.
    const half underlineWeight = ComputeWeightOfUnderlineInverted(in.underlineStyle,
                                                                  in.clipSpacePosition.xy,
                                                                  in.viewportSize,
                                                                  in.cellOffset,
                                                                  dimensions->underlineOffset,
                                                                  dimensions->underlineThickness,
                                                                  dimensions->textureSize,
                                                                  in.textureOffset,
                                                                  in.textureCoordinate,
                                                                  dimensions->cellSize,
                                                                  texture,
                                                                  textureSampler,
                                                                  dimensions->scale);
    if (underlineWeight == 0 && bwColor.x == 1 && bwColor.y == 1 && bwColor.z == 1) {
        discard_fragment();
    }

    half4 textColor = RemapColor(in.textColor * 17.0, backgroundColor, static_cast<float4>(bwColor), colorModels);
    return mix(textColor, in.underlineColor, underlineWeight);
}

#pragma mark - Monochrome
// macOS 10.14+ code path (no subpixel AA support)

// Color and return sample from texture
fragment half4
iTermTextFragmentShaderMonochrome(iTermTextVertexFunctionOutputMonochrome in [[stage_in]],
                                  texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]],
                                  texture2d<half> drawable [[ texture(iTermTextureIndexBackground) ]],
                                  constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    half4 textureColor = texture.sample(textureSampler, in.textureCoordinate);
    // These values were arrived at experimentally.
    // They're not a perfect match for how the system recolors glyphs but it's close.
    half4 result = in.textColor;
    half power = 3.0 - 2.0 * (0.3 * in.textColor.x + 0.59 * in.textColor.y + 0.11 * in.textColor.z);
    result.w *= pow(textureColor.w, power);
    return result;
}

// Return sample from texture plus underline
fragment half4
iTermTextFragmentShaderMonochromeUnderlinedEmoji(iTermTextVertexFunctionOutput in [[stage_in]],
                                                 texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]],
                                                 texture2d<half> drawable [[ texture(iTermTextureIndexBackground) ]],
                                                 constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    half4 textureColor = texture.sample(textureSampler, in.textureCoordinate);

    // Underlined emoji code path
    const half underlineWeight = ComputeWeightOfUnderlineRegular(in.underlineStyle,
                                                                 in.clipSpacePosition.xy,
                                                                 in.viewportSize,
                                                                 in.cellOffset,
                                                                 dimensions->underlineOffset,
                                                                 dimensions->underlineThickness,
                                                                 dimensions->textureSize,
                                                                 in.textureOffset,
                                                                 in.textureCoordinate,
                                                                 dimensions->cellSize,
                                                                 texture,
                                                                 textureSampler,
                                                                 dimensions->scale);
    return mix(textureColor,
               in.underlineColor,
               underlineWeight);
}

// Return colored sample from texture plus underline
fragment half4
iTermTextFragmentShaderMonochromeUnderlined(iTermTextVertexFunctionOutput in [[stage_in]],
                                            texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]],
                                            texture2d<half> drawable [[ texture(iTermTextureIndexBackground) ]],
                                            constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    half4 textureColor = texture.sample(textureSampler, in.textureCoordinate);

    // Underlined not emoji.
    const half underlineWeight = ComputeWeightOfUnderlineRegular(in.underlineStyle,
                                                                 in.clipSpacePosition.xy,
                                                                 in.viewportSize,
                                                                 in.cellOffset,
                                                                 dimensions->underlineOffset,
                                                                 dimensions->underlineThickness,
                                                                 dimensions->textureSize,
                                                                 in.textureOffset,
                                                                 in.textureCoordinate,
                                                                 dimensions->cellSize,
                                                                 texture,
                                                                 textureSampler,
                                                                 dimensions->scale);

    half4 recoloredTextColor = static_cast<half4>(in.textColor);
    const half power = 3.0 - 2.0 * (0.3 * in.textColor.x + 0.59 * in.textColor.y + 0.11 * in.textColor.z);
    recoloredTextColor.w *= pow(textureColor.w, power);

    // I could eke out a little speed by passing a half4 from the vector shader but this is so slow I'd rather not add the complexity.
    return mix(recoloredTextColor,
               in.underlineColor,
               underlineWeight);
}
