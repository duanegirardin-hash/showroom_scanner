package com.example.showroom_scanner

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.showroom_scanner/documents",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "savePublicCsv" -> {
                    val filename = call.argument<String>("filename")
                    val content = call.argument<String>("content")
                    if (filename.isNullOrBlank() || content == null) {
                        result.error("bad_args", "filename and content required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(saveCsvToPublicDocuments(filename, content))
                    } catch (e: Exception) {
                        result.error("save_failed", e.message, null)
                    }
                }
                "savePublicCsvInShowroomExports" -> {
                    val customerFolder = call.argument<String>("customerFolder")
                    val filename = call.argument<String>("filename")
                    val content = call.argument<String>("content")
                    if (customerFolder.isNullOrBlank() ||
                        filename.isNullOrBlank() ||
                        content == null
                    ) {
                        result.error(
                            "bad_args",
                            "customerFolder, filename and content required",
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    if (!isSafeSinglePathSegment(customerFolder) ||
                        customerFolder.contains('/') ||
                        customerFolder.contains('\\')
                    ) {
                        result.error("bad_args", "invalid customerFolder", null)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(
                            saveCsvToPublicDocumentsShowroomExports(
                                customerFolder,
                                filename,
                                content,
                            ),
                        )
                    } catch (e: Exception) {
                        result.error("save_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isSafeSinglePathSegment(segment: String): Boolean {
        if (segment.isEmpty()) return false
        if (segment == "." || segment == "..") return false
        return true
    }

    private fun mediaStoreCsvDisplayNameExists(
        displayName: String,
        relativePath: String,
    ): Boolean {
        val resolver = applicationContext.contentResolver
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection =
            "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND ${MediaStore.MediaColumns.RELATIVE_PATH} = ?"
        val selectionArgs = arrayOf(displayName, relativePath)
        val uri = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        resolver.query(uri, projection, selection, selectionArgs, null)?.use { cursor ->
            return cursor.count > 0
        }
        return false
    }

    private fun saveCsvToPublicDocumentsShowroomExports(
        customerFolder: String,
        filename: String,
        content: String,
    ): String {
        val bytes = content.toByteArray(Charsets.UTF_8)
        val relativeInsideDocuments = "Showroom_Sync/Exported orders/$customerFolder"
        val documentsDir =
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
        val relativePath =
            "${Environment.DIRECTORY_DOCUMENTS}/$relativeInsideDocuments/"
        val outDir = File(documentsDir, relativeInsideDocuments)

        val lower = filename.lowercase()
        val ext = ".csv"
        val uniqueFilename =
            if (lower.endsWith(ext)) {
                val stem = filename.substring(0, filename.length - ext.length)
                var candidate = filename
                var n = 2
                while (true) {
                    val occupied =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            mediaStoreCsvDisplayNameExists(candidate, relativePath)
                        } else {
                            File(outDir, candidate).exists()
                        }
                    if (!occupied) break
                    candidate = "${stem}_$n$ext"
                    n++
                }
                candidate
            } else {
                filename
            }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values =
                ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, uniqueFilename)
                    put(MediaStore.MediaColumns.MIME_TYPE, "text/csv")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                }
            val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val uri =
                resolver.insert(collection, values)
                    ?: error("MediaStore insert failed for $uniqueFilename")
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: error("Could not open output stream for $uniqueFilename")
            return File(documentsDir, "$relativeInsideDocuments/$uniqueFilename").absolutePath
        }
        if (!outDir.exists()) {
            outDir.mkdirs()
        }
        val outFile = File(outDir, uniqueFilename)
        FileOutputStream(outFile).use { it.write(bytes) }
        return outFile.absolutePath
    }

    /**
     * Writes to shared Documents (visible in Samsung My Files). API 29+ uses MediaStore;
     * older APIs use direct file I/O with [Environment.DIRECTORY_DOCUMENTS].
     */
    private fun saveCsvToPublicDocuments(filename: String, content: String): String {
        val bytes = content.toByteArray(Charsets.UTF_8)
        val documentsDir =
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values =
                ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
                    put(MediaStore.MediaColumns.MIME_TYPE, "text/csv")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOCUMENTS)
                }
            val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val uri =
                resolver.insert(collection, values)
                    ?: error("MediaStore insert failed for $filename")
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: error("Could not open output stream for $filename")
            return File(documentsDir, filename).absolutePath
        }
        if (!documentsDir.exists()) {
            documentsDir.mkdirs()
        }
        val outFile = File(documentsDir, filename)
        FileOutputStream(outFile).use { it.write(bytes) }
        return outFile.absolutePath
    }
}
