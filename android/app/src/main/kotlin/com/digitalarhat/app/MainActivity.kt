package com.digitalarhat.app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.android.RenderMode

class MainActivity: FlutterFragmentActivity() {
    
    override fun getRenderMode(): RenderMode {
        // Texture mode performance ke liye behtar hai
        return RenderMode.texture
    }

    // Baaqi extra functions (onCreate, onPause etc.) ki zaroorat nahi 
    // jab tak aap koi custom Android code na likh rahe hon.
    // FlutterFragmentActivity khud sab handle kar leta hai.
}