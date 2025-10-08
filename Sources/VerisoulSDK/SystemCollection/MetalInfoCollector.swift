import Metal

class MetalInfoCollector {
    static func collect() -> [String: Any]? {
        let startTime = CFAbsoluteTimeGetCurrent()
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }
        
        var data = [
            "gpu_name": device.name,
            "registry_id": device.registryID,
            "max_threads_per_threadgroup": MTLSizeCodable(mtlSize: device.maxThreadsPerThreadgroup).dictionary,
            "max_threadgroup_memory": device.maxThreadgroupMemoryLength,
            "max_buffer_length": device.maxBufferLength,
            "has_unified_memory": device.hasUnifiedMemory,
            "programmable_sample_positions": device.areProgrammableSamplePositionsSupported,
            "raster_order_groups": device.areRasterOrderGroupsSupported,
            "32_bit_float_filtering": device.supports32BitFloatFiltering,
            "32_bit_msaa": device.supports32BitMSAA,
            "query_texture_lod": device.supportsQueryTextureLOD,
            "pull_model_interpolation": device.supportsPullModelInterpolation,
            "raytracing": device.supportsRaytracing,
            "function_pointers": device.supportsFunctionPointers,
            "primitive_motion_blur": device.supportsPrimitiveMotionBlur
        ] as [String : Any]
        if #available(iOS 16.0, *) {
            data["recommended_max_working_set"] = device.recommendedMaxWorkingSetSize
        }
        
        if #available(iOS 15.0, *) {
            data["raytracing_from_render"] = device.supportsRaytracingFromRender
        }
        let endTime = CFAbsoluteTimeGetCurrent()
        UnifiedLogger.shared.metric(value: (endTime - startTime),
                                    name: "metal_duration",
                                    className: String(describing: MetalInfoCollector.self))
        return data
    }
}
