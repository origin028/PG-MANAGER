package com.example.resident_app

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.originpg.resident/native_upi"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "launchPhonePeDirect" -> {
                    val uriString = call.argument<String>("uri") ?: ""
                    val packageName = call.argument<String>("package") ?: "com.phonepe.app"

                    try {
                        val pm = packageManager
                        val isInstalled = try {
                            pm.getPackageInfo(packageName, 0)
                            true
                        } catch (e: PackageManager.NameNotFoundException) {
                            false
                        }

                        if (!isInstalled) {
                            result.success(mapOf(
                                "status" to "PACKAGE_NOT_INSTALLED",
                                "message" to "Package $packageName is not installed on this device"
                            ))
                            return@setMethodCallHandler
                        }

                        val parsedUri = Uri.parse(uriString)

                        // 1. Try explicit Intent with ACTION_VIEW, standard upi:// scheme, and explicit package
                        val explicitUpiIntent = Intent(Intent.ACTION_VIEW, parsedUri).apply {
                            setPackage(packageName)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        if (explicitUpiIntent.resolveActivity(pm) != null) {
                            startActivity(explicitUpiIntent)
                            result.success(mapOf(
                                "status" to "SUCCESS",
                                "method" to "EXPLICIT_UPI_INTENT"
                            ))
                            return@setMethodCallHandler
                        }

                        // 2. Try phonepe:// scheme with explicit package
                        val phonePeUri = parsedUri.buildUpon().scheme("phonepe").build()
                        val phonePeIntent = Intent(Intent.ACTION_VIEW, phonePeUri).apply {
                            setPackage(packageName)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        if (phonePeIntent.resolveActivity(pm) != null) {
                            startActivity(phonePeIntent)
                            result.success(mapOf(
                                "status" to "SUCCESS",
                                "method" to "PHONEPE_SCHEME_INTENT"
                            ))
                            return@setMethodCallHandler
                        }

                        // 3. Try ppe:// scheme with explicit package
                        val ppeUri = parsedUri.buildUpon().scheme("ppe").build()
                        val ppeIntent = Intent(Intent.ACTION_VIEW, ppeUri).apply {
                            setPackage(packageName)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        if (ppeIntent.resolveActivity(pm) != null) {
                            startActivity(ppeIntent)
                            result.success(mapOf(
                                "status" to "SUCCESS",
                                "method" to "PPE_SCHEME_INTENT"
                            ))
                            return@setMethodCallHandler
                        }

                        // 4. Try launch intent for package (opens PhonePe app directly)
                        val launchIntent = pm.getLaunchIntentForPackage(packageName)
                        if (launchIntent != null) {
                            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(launchIntent)
                            result.success(mapOf(
                                "status" to "SUCCESS",
                                "method" to "MAIN_LAUNCH_INTENT"
                            ))
                            return@setMethodCallHandler
                        }

                        // 5. Activity not resolved - strictly never fall back to generic chooser
                        result.success(mapOf(
                            "status" to "ACTIVITY_NOT_RESOLVED",
                            "message" to "No compatible activity found in package $packageName"
                        ))
                    } catch (e: Exception) {
                        result.error("LAUNCH_ERROR", e.localizedMessage, null)
                    }
                }
                "isPackageInstalled" -> {
                    val packageName = call.argument<String>("package") ?: ""
                    val isInstalled = try {
                        packageManager.getPackageInfo(packageName, 0)
                        true
                    } catch (e: PackageManager.NameNotFoundException) {
                        false
                    }
                    result.success(isInstalled)
                }
                else -> result.notImplemented()
            }
        }
    }
}
