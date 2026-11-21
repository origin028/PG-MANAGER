package com.example.resident_app

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.ArrayList
import java.util.HashMap
import java.util.HashSet

class MainActivity : FlutterActivity() {
    private val NATIVE_CHANNEL = "com.originpg.resident/native_upi"
    private val UPI_INDIA_CHANNEL = "com.az.upi_india"
    private val UPI_PAYMENT_REQUEST_CODE = 4201
    private val UPI_INDIA_REQUEST_CODE = 512078

    private var pendingUpiResult: MethodChannel.Result? = null
    private var lastLaunchedPackage: String? = null
    private var isUpiIndiaCaller = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Native PG Management Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledUpiApps" -> {
                    try {
                        val apps = getInstalledUpiAppsList()
                        result.success(apps)
                    } catch (e: Exception) {
                        result.error("DISCOVERY_ERROR", e.localizedMessage, null)
                    }
                }

                "launchUpiIntent" -> {
                    handleLaunchUpiIntent(call, result)
                }

                "launchPhonePeDirect" -> {
                    // Route PhonePe directly through standard UPI intent (no FLAG_ACTIVITY_NEW_TASK)
                    val uriString = call.argument<String>("uri") ?: ""
                    val packageName = call.argument<String>("package") ?: "com.phonepe.app"
                    callLaunchDirect(uriString, packageName, result)
                }

                "isPackageInstalled" -> {
                    val packageName = call.argument<String>("package") ?: ""
                    result.success(isPackageInstalled(packageName))
                }

                else -> result.notImplemented()
            }
        }

        // UPI India Plugin Standard Channel (com.az.upi_india)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPI_INDIA_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAllUpiApps" -> {
                    try {
                        val apps = getAllUpiAppsWithIcons()
                        result.success(apps)
                    } catch (e: Exception) {
                        result.error("package_get_failed", "Failed to get list of installed UPI apps: ${e.localizedMessage}", null)
                    }
                }

                "startTransaction" -> {
                    handleStartTransaction(call, result)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        if (packageName.isBlank()) return false
        return try {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, PackageManager.GET_ACTIVITIES)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun getBitmapFromDrawable(drawable: Drawable): Bitmap {
        val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 96
        val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 96
        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bmp
    }

    private fun getInstalledUpiAppsList(): List<Map<String, String>> {
        val pm = packageManager
        val probeUri = Uri.parse("upi://pay?pa=test@upi&pn=Payee&am=1.00&cu=INR&mode=04")
        val intent = Intent(Intent.ACTION_VIEW, probeUri)
        @Suppress("DEPRECATION")
        val resolveInfos = pm.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)

        val seenPackages = HashSet<String>()
        val apps = ArrayList<Map<String, String>>()
        for (info in resolveInfos) {
            val pkg = info.activityInfo?.packageName ?: continue
            if (seenPackages.add(pkg)) {
                val label = info.loadLabel(pm)?.toString()?.trim()
                apps.add(
                    mapOf(
                        "packageName" to pkg,
                        "name" to (if (!label.isNullOrEmpty()) label else pkg),
                    )
                )
            }
        }
        return apps
    }

    private fun getAllUpiAppsWithIcons(): List<Map<String, Any>> {
        val packages = ArrayList<Map<String, Any>>()
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("upi://pay?pa=test@upi&pn=Test&tn=GetAllApps&am=10.00&cu=INR&mode=04"))
        val pm = packageManager
        @Suppress("DEPRECATION")
        val resolveInfoList = pm.queryIntentActivities(intent, 0)
        val seen = HashSet<String>()

        for (resolveInfo in resolveInfoList) {
            val pkg = resolveInfo.activityInfo?.packageName ?: continue
            if (!seen.add(pkg)) continue
            try {
                val label = pm.getApplicationLabel(pm.getApplicationInfo(pkg, PackageManager.GET_META_DATA)).toString()
                val dIcon = pm.getApplicationIcon(pkg)
                val bIcon = getBitmapFromDrawable(dIcon)
                val stream = ByteArrayOutputStream()
                bIcon.compress(Bitmap.CompressFormat.PNG, 100, stream)
                val icon = stream.toByteArray()

                val m = HashMap<String, Any>()
                m["packageName"] = pkg
                m["name"] = if (label.isNotBlank()) label else pkg
                m["icon"] = icon
                packages.add(m)
            } catch (e: Exception) {
                val m = HashMap<String, Any>()
                m["packageName"] = pkg
                m["name"] = pkg
                packages.add(m)
            }
        }
        return packages
    }

    private fun handleStartTransaction(call: MethodCall, result: MethodChannel.Result) {
        if (pendingUpiResult != null) {
            result.error("transaction_in_progress", "Another transaction is already in progress.", null)
            return
        }

        val app = call.argument<String>("app") ?: "in.org.npci.upiapp"
        val receiverUpiId = call.argument<String>("receiverUpiId") ?: ""
        val receiverName = call.argument<String>("receiverName") ?: ""
        val transactionRefId = call.argument<String>("transactionRefId")
        val transactionNote = call.argument<String>("transactionNote")
        val amount = call.argument<String>("amount") ?: "1.00"
        val currency = call.argument<String>("currency") ?: "INR"
        val url = call.argument<String>("url")
        val merchantId = call.argument<String>("merchantId")

        try {
            val cleanPn = receiverName.replace("'", "").trim()
            val cleanNote = transactionNote?.replace("+", " ")?.replace("'", "")?.replace(Regex("[^A-Za-z0-9 ]"), " ")?.trim()
            val cleanTr = transactionRefId?.replace(Regex("[^A-Za-z0-9]"), "")?.trim()

            var uriString = "upi://pay?pa=" + receiverUpiId.trim() +
                    "&pn=" + Uri.encode(cleanPn) +
                    "&am=" + Uri.encode(amount.trim())
            if (!cleanNote.isNullOrBlank()) uriString += "&tn=" + Uri.encode(cleanNote)
            if (!cleanTr.isNullOrBlank()) uriString += "&tr=" + Uri.encode(cleanTr)
            uriString += "&cu=" + (if (!currency.isNullOrBlank()) Uri.encode(currency.trim()) else "INR")
            if (!url.isNullOrBlank()) uriString += "&url=" + Uri.encode(url.trim())
            if (!merchantId.isNullOrBlank()) uriString += "&mc=" + Uri.encode(merchantId.trim())
            uriString += "&mode=04"

            val uri = Uri.parse(uriString)
            Log.d("UpiIndiaNative", "Starting UPI transaction app=$app uri=$uriString")

            if (!isPackageInstalled(app)) {
                Log.d("UpiIndiaNative", "App $app is not installed.")
                result.error("app_not_installed", "Requested app not installed", null)
                return
            }

            val intent = Intent(Intent.ACTION_VIEW, uri)
            intent.setPackage(app)

            pendingUpiResult = result
            lastLaunchedPackage = app
            isUpiIndiaCaller = true
            @Suppress("DEPRECATION")
            startActivityForResult(intent, UPI_INDIA_REQUEST_CODE)
        } catch (ex: Exception) {
            Log.e("UpiIndiaNative", "startTransaction error", ex)
            result.error("invalid_parameters", "Transaction parameters are invalid", null)
        }
    }

    private fun handleLaunchUpiIntent(call: MethodCall, result: MethodChannel.Result) {
        if (pendingUpiResult != null) {
            result.success(
                mapOf(
                    "status" to "FAILURE",
                    "responseCode" to "TXN_IN_PROGRESS",
                    "message" to "Another UPI payment is already in progress.",
                )
            )
            return
        }

        val rawUri = call.argument<String>("uri")?.trim() ?: ""
        val targetPackage = call.argument<String>("packageName")?.trim()

        if (rawUri.isEmpty()) {
            result.success(
                mapOf(
                    "status" to "FAILURE",
                    "responseCode" to "INVALID_URI",
                    "message" to "UPI URI is empty.",
                )
            )
            return
        }

        try {
            if (!targetPackage.isNullOrEmpty() && !isPackageInstalled(targetPackage)) {
                result.success(
                    mapOf(
                        "status" to "APP_NOT_INSTALLED",
                        "packageName" to targetPackage,
                        "message" to "Selected UPI application ($targetPackage) is not installed.",
                    )
                )
                return
            }

            // Ensure mode=04 is included, and strip package and mc params
            val parsed = Uri.parse(rawUri)
            val rawQuery = parsed.encodedQuery ?: ""
            val queryPairs = rawQuery.split("&")
                .filter {
                    it.isNotEmpty() &&
                    !it.substringBefore("=").equals("package", ignoreCase = true) &&
                    !it.substringBefore("=").equals("mc", ignoreCase = true)
                }
                .toMutableList()

            if (queryPairs.none { it.substringBefore("=").equals("mode", ignoreCase = true) }) {
                queryPairs.add("mode=04")
            }

            val cleanUri = parsed.buildUpon().encodedQuery(queryPairs.joinToString("&")).build()
            Log.d("DirectUpiNative", "Launching UPI intent app=${targetPackage ?: "chooser"} uri=$cleanUri")

            val upiIntent = Intent(Intent.ACTION_VIEW, cleanUri)
            if (!targetPackage.isNullOrEmpty()) {
                upiIntent.setPackage(targetPackage)
            }

            pendingUpiResult = result
            lastLaunchedPackage = targetPackage
            isUpiIndiaCaller = false
            @Suppress("DEPRECATION")
            startActivityForResult(upiIntent, UPI_PAYMENT_REQUEST_CODE)
        } catch (e: Exception) {
            pendingUpiResult = null
            lastLaunchedPackage = null
            result.success(
                mapOf(
                    "status" to "FAILURE",
                    "responseCode" to "LAUNCH_ERROR",
                    "message" to (e.localizedMessage ?: "Failed to launch UPI application."),
                )
            )
        }
    }

    private fun callLaunchDirect(uriString: String, packageName: String, result: MethodChannel.Result) {
        if (!isPackageInstalled(packageName)) {
            result.success(
                mapOf(
                    "status" to "PACKAGE_NOT_INSTALLED",
                    "message" to "Package $packageName is not installed on this device"
                )
            )
            return
        }

        try {
            val parsed = Uri.parse(uriString)
            val queryPairs = (parsed.encodedQuery ?: "").split("&")
                .filter {
                    it.isNotEmpty() &&
                    !it.substringBefore("=").equals("package", ignoreCase = true) &&
                    !it.substringBefore("=").equals("mc", ignoreCase = true)
                }
                .toMutableList()
            if (queryPairs.none { it.substringBefore("=").equals("mode", ignoreCase = true) }) {
                queryPairs.add("mode=04")
            }
            val cleanUri = parsed.buildUpon().encodedQuery(queryPairs.joinToString("&")).build()

            val intent = Intent(Intent.ACTION_VIEW, cleanUri)
            intent.setPackage(packageName)

            pendingUpiResult = result
            lastLaunchedPackage = packageName
            isUpiIndiaCaller = false
            @Suppress("DEPRECATION")
            startActivityForResult(intent, UPI_PAYMENT_REQUEST_CODE)
        } catch (e: Exception) {
            result.error("LAUNCH_ERROR", e.localizedMessage, null)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != UPI_PAYMENT_REQUEST_CODE && requestCode != UPI_INDIA_REQUEST_CODE) {
            return
        }

        val callback = pendingUpiResult ?: return
        val pkg = lastLaunchedPackage
        val wasUpiIndia = isUpiIndiaCaller || (requestCode == UPI_INDIA_REQUEST_CODE)
        pendingUpiResult = null
        lastLaunchedPackage = null
        isUpiIndiaCaller = false

        if (wasUpiIndia) {
            if (data != null) {
                val rawResponse = data.getStringExtra("response")
                if (!rawResponse.isNullOrBlank()) {
                    Log.d("UpiIndiaNative", "RAW RESPONSE: $rawResponse")
                    callback.success(rawResponse)
                } else {
                    val status = data.getStringExtra("Status") ?: data.getStringExtra("status") ?: "SUCCESS"
                    val txnId = data.getStringExtra("txnId") ?: data.getStringExtra("txnid") ?: ""
                    val txnRef = data.getStringExtra("txnRef") ?: data.getStringExtra("txnref") ?: ""
                    val approvalRef = data.getStringExtra("ApprovalRefNo") ?: data.getStringExtra("approvalrefno") ?: ""
                    val respCode = data.getStringExtra("responseCode") ?: data.getStringExtra("responsecode") ?: "00"
                    val synthetic = "txnId=$txnId&responseCode=$respCode&ApprovalRefNo=$approvalRef&Status=$status&txnRef=$txnRef"
                    Log.d("UpiIndiaNative", "SYNTHETIC RESPONSE: $synthetic")
                    callback.success(synthetic)
                }
            } else {
                Log.d("UpiIndiaNative", "Received NULL data from UPI app")
                callback.error("user_canceled", "User cancelled the transaction", null)
            }
            return
        }

        // DirectUpi native Map result handling
        val rawResponse = data?.getStringExtra("response") ?: ""
        val parsedMap = HashMap<String, String>()
        if (rawResponse.isNotBlank()) {
            for (pair in rawResponse.split("&")) {
                val idx = pair.indexOf('=')
                if (idx > 0) {
                    val k = Uri.decode(pair.substring(0, idx)).trim().lowercase()
                    val v = Uri.decode(pair.substring(idx + 1)).trim()
                    parsedMap[k] = v
                }
            }
        }

        val rawStatus = (parsedMap["status"] ?: data?.getStringExtra("Status") ?: data?.getStringExtra("status") ?: "").trim().uppercase()
        val txnId = parsedMap["txnid"] ?: data?.getStringExtra("txnId") ?: data?.getStringExtra("txnid")
        val txnRef = parsedMap["txnref"] ?: data?.getStringExtra("txnRef") ?: data?.getStringExtra("txnref")
        val approvalRefNo = parsedMap["approvalrefno"] ?: data?.getStringExtra("ApprovalRefNo") ?: data?.getStringExtra("approvalrefno")
        val responseCode = parsedMap["responsecode"] ?: data?.getStringExtra("responseCode") ?: data?.getStringExtra("responsecode")
        val messageExtra = parsedMap["message"] ?: data?.getStringExtra("message")

        val normalizedStatus = when {
            rawStatus == "SUCCESS" -> "SUCCESS"
            rawStatus == "SUBMITTED" -> "SUBMITTED"
            rawStatus == "PENDING" -> "PENDING"
            rawStatus == "FAILURE" || rawStatus == "FAILED" -> "FAILURE"
            rawStatus == "CANCELLED" || rawStatus == "CANCELED" -> "CANCELLED"
            data == null && resultCode == Activity.RESULT_CANCELED -> "CANCELLED"
            rawResponse.isBlank() && resultCode == Activity.RESULT_CANCELED -> "CANCELLED"
            else -> "UNKNOWN"
        }

        val payload = HashMap<String, Any?>()
        payload["status"] = normalizedStatus
        payload["txnId"] = txnId
        payload["txnRef"] = txnRef
        payload["approvalRefNo"] = approvalRefNo
        payload["responseCode"] = responseCode
        payload["message"] = messageExtra
        payload["rawResponse"] = rawResponse
        payload["resultCode"] = resultCode
        payload["packageName"] = pkg

        Log.d(
            "DirectUpiNative",
            "UPI activity result app=${pkg ?: "unknown"} resultCode=$resultCode status=$normalizedStatus responseCode=${responseCode ?: "-"} hasTxnId=${!txnId.isNullOrBlank()}"
        )

        callback.success(payload)
    }
}
