package com.example.fylesync_frontend

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.fylesync/native"
    private var pendingResult: MethodChannel.Result? = null
    private val PICK_FILE_REQUEST_CODE = 1001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFile" -> {
                    pendingResult = result
                    try {
                        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                            type = "*/*"
                            addCategory(Intent.CATEGORY_OPENABLE)
                        }
                        startActivityForResult(
                            Intent.createChooser(intent, "Seleccionar archivo para subir a FyleSync"),
                            PICK_FILE_REQUEST_CODE
                        )
                    } catch (e: Exception) {
                        result.error("INTENT_ERROR", e.message, null)
                        pendingResult = null
                    }
                }
                "openUrl" -> {
                    val urlString = call.argument<String>("url")
                    if (urlString != null) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(urlString))
                            val chooser = Intent.createChooser(intent, "Abrir con").apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(chooser)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "URL no especificada", null)
                    }
                }
                "listDirectory" -> {
                    val dirPath = call.argument<String>("path")
                    if (dirPath != null) {
                        try {
                            var targetDir = File(dirPath)
                            if (!targetDir.exists()) {
                                val parent = targetDir.parentFile
                                if (parent != null && parent.exists() && parent.isDirectory) {
                                    val matching = parent.listFiles()?.firstOrNull { it.name.equals(targetDir.name, ignoreCase = true) }
                                    if (matching != null && matching.isDirectory) {
                                        targetDir = matching
                                    }
                                }
                            }
                            if (targetDir.exists() && targetDir.isDirectory) {
                                val filesList = ArrayList<Map<String, Any>>()
                                targetDir.listFiles()?.forEach { file ->
                                    if (file.isFile && !file.name.startsWith(".")) {
                                        val map = HashMap<String, Any>()
                                        map["name"] = file.name
                                        map["path"] = file.absolutePath
                                        map["size"] = file.length()
                                        map["lastModified"] = file.lastModified()
                                        filesList.add(map)
                                    }
                                }
                                result.success(filesList)
                            } else {
                                result.success(ArrayList<Map<String, Any>>())
                            }
                        } catch (e: Exception) {
                            result.error("LIST_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Ruta no especificada", null)
                    }
                }
                "readFileBytes" -> {
                    val filePath = call.argument<String>("path")
                    if (filePath != null) {
                        try {
                            val file = File(filePath)
                            if (file.exists() && file.isFile) {
                                result.success(file.readBytes())
                            } else {
                                result.error("NOT_FOUND", "Archivo no encontrado: $filePath", null)
                            }
                        } catch (e: Exception) {
                            result.error("READ_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Ruta no especificada", null)
                    }
                }
                "saveFileBytes" -> {
                    val dirPath = call.argument<String>("dirPath")
                    val fileName = call.argument<String>("fileName")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (dirPath != null && fileName != null && bytes != null) {
                        try {
                            var targetDir = File(dirPath)
                            if (!targetDir.exists()) {
                                val parent = targetDir.parentFile
                                if (parent != null && parent.exists()) {
                                    val matching = parent.listFiles()?.firstOrNull { it.name.equals(targetDir.name, ignoreCase = true) }
                                    if (matching != null) targetDir = matching
                                }
                            }
                            if (!targetDir.exists()) {
                                targetDir.mkdirs()
                            }
                            val targetFile = File(targetDir, fileName)
                            targetFile.writeBytes(bytes)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SAVE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Parámetros incompletos", null)
                    }
                }
                "requestManageStorage" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            if (!Environment.isExternalStorageManager()) {
                                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                                    data = Uri.parse("package:" + applicationContext.packageName)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success(false)
                            } else {
                                result.success(true)
                            }
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("PERMISSION_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_FILE_REQUEST_CODE) {
            val res = pendingResult
            pendingResult = null

            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri: Uri = data.data!!
                try {
                    var fileName = "archivo"
                    var fileSize = 0L

                    contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                        val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                        if (cursor.moveToFirst()) {
                            if (nameIndex != -1) fileName = cursor.getString(nameIndex) ?: "archivo"
                            if (sizeIndex != -1) fileSize = cursor.getLong(sizeIndex)
                        }
                    }

                    val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: ByteArray(0)
                    if (fileSize == 0L) fileSize = bytes.size.toLong()

                    val resultMap = hashMapOf(
                        "name" to fileName,
                        "size" to fileSize,
                        "bytes" to bytes
                    )
                    res?.success(resultMap)
                } catch (e: Exception) {
                    res?.error("READ_ERROR", e.message, null)
                }
            } else {
                res?.success(null)
            }
        }
    }
}
