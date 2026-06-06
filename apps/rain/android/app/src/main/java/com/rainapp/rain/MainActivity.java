package com.rainapp.rain;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.io.File;
import java.io.FileInputStream;
import java.io.OutputStream;

public final class MainActivity extends FlutterActivity {
  private static final int SAVE_REQUEST_CODE = 9107;

  private MethodChannel.Result pendingSaveResult;
  private String pendingSourcePath;

  @Override
  public void configureFlutterEngine(FlutterEngine flutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "rain/file_export")
        .setMethodCallHandler(
            (MethodCall call, MethodChannel.Result result) -> {
              if ("saveReceivedFile".equals(call.method)) {
                saveReceivedFile(call, result);
                return;
              }
              result.notImplemented();
            });
  }

  private void saveReceivedFile(MethodCall call, MethodChannel.Result result) {
    if (pendingSaveResult != null) {
      result.error("busy", "Another save is already open.", null);
      return;
    }

    final String sourcePath = call.argument("sourcePath");
    final String requestedFileName = call.argument("fileName");
    final String requestedMimeType = call.argument("mimeType");
    final String fileName =
        requestedFileName == null || requestedFileName.isBlank() ? "rain-file" : requestedFileName;
    final String mimeType =
        requestedMimeType == null || requestedMimeType.isBlank()
            ? "application/octet-stream"
            : requestedMimeType;

    if (sourcePath == null || sourcePath.isBlank() || !new File(sourcePath).exists()) {
      result.error("missing_source", "Received file is not available.", null);
      return;
    }

    pendingSaveResult = result;
    pendingSourcePath = sourcePath;

    final Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
    intent.addCategory(Intent.CATEGORY_OPENABLE);
    intent.setType(mimeType);
    intent.putExtra(Intent.EXTRA_TITLE, fileName);

    try {
      startActivityForResult(intent, SAVE_REQUEST_CODE);
    } catch (Exception error) {
      clearPendingSave();
      result.error("save_unavailable", "Could not save file. Choose another location.", error.getMessage());
    }
  }

  @Override
  @SuppressWarnings("deprecation")
  protected void onActivityResult(int requestCode, int resultCode, Intent data) {
    if (requestCode != SAVE_REQUEST_CODE) {
      super.onActivityResult(requestCode, resultCode, data);
      return;
    }

    final MethodChannel.Result result = pendingSaveResult;
    final String sourcePath = pendingSourcePath;
    if (result == null || sourcePath == null) {
      clearPendingSave();
      return;
    }

    final Uri uri = data == null ? null : data.getData();
    if (resultCode != Activity.RESULT_OK || uri == null) {
      clearPendingSave();
      result.success(false);
      return;
    }

    new Thread(() -> copyReceivedFile(uri, sourcePath, result)).start();
  }

  private void copyReceivedFile(Uri uri, String sourcePath, MethodChannel.Result result) {
    try (OutputStream output = getContentResolver().openOutputStream(uri);
        FileInputStream input = new FileInputStream(new File(sourcePath))) {
      if (output == null) {
        throw new IllegalStateException("Could not open destination.");
      }
      final byte[] buffer = new byte[64 * 1024];
      int read;
      while ((read = input.read(buffer)) != -1) {
        output.write(buffer, 0, read);
      }
      runOnUiThread(
          () -> {
            clearPendingSave();
            result.success(true);
          });
    } catch (Exception error) {
      runOnUiThread(
          () -> {
            clearPendingSave();
            result.error("save_failed", "Could not save file. Choose another location.", error.getMessage());
          });
    }
  }

  private void clearPendingSave() {
    pendingSaveResult = null;
    pendingSourcePath = null;
  }
}
