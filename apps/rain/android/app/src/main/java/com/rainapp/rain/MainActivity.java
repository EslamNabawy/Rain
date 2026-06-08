package com.rainapp.rain;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.io.File;
import java.io.FileInputStream;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.Map;

public final class MainActivity extends FlutterActivity {
  private static final int SAVE_REQUEST_CODE = 9107;
  private static final int MEDIA_PERMISSION_REQUEST_CODE = 9108;
  private static final String FILE_EXPORT_CHANNEL = "rain/file_export";
  private static final String MEDIA_PERMISSION_CHANNEL = "rain/media_permissions";
  private static final String MEDIA_PERMISSION_METHOD_REQUEST = "request";
  private static final String PERMISSION_RECORD_AUDIO = Manifest.permission.RECORD_AUDIO;
  private static final String PERMISSION_CAMERA = Manifest.permission.CAMERA;

  private MethodChannel.Result pendingSaveResult;
  private String pendingSourcePath;
  private MethodChannel.Result pendingMediaPermissionResult;

  @Override
  public void configureFlutterEngine(FlutterEngine flutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), FILE_EXPORT_CHANNEL)
        .setMethodCallHandler(
            (MethodCall call, MethodChannel.Result result) -> {
              if ("saveReceivedFile".equals(call.method)) {
                saveReceivedFile(call, result);
                return;
              }
              result.notImplemented();
            });
    new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), MEDIA_PERMISSION_CHANNEL)
        .setMethodCallHandler(
            (MethodCall call, MethodChannel.Result result) -> {
              if (MEDIA_PERMISSION_METHOD_REQUEST.equals(call.method)) {
                requestMediaPermissions(call, result);
                return;
              }
              result.notImplemented();
            });
  }

  private void requestMediaPermissions(MethodCall call, MethodChannel.Result result) {
    if (pendingMediaPermissionResult != null) {
      result.error("busy", "Another media permission request is already open.", null);
      return;
    }

    final Boolean requireVideoArg = call.argument("requireVideo");
    final boolean requireVideo = requireVideoArg != null && requireVideoArg;

    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
      result.success(mediaPermissionResult(requireVideo));
      return;
    }

    final String[] permissions = mediaPermissions(requireVideo);
    if (hasPermissions(permissions)) {
      result.success(mediaPermissionResult(requireVideo));
      return;
    }

    pendingMediaPermissionResult = result;
    requestPermissions(permissions, MEDIA_PERMISSION_REQUEST_CODE);
  }

  private String[] mediaPermissions(boolean requireVideo) {
    if (requireVideo) {
      return new String[] {PERMISSION_RECORD_AUDIO, PERMISSION_CAMERA};
    }
    return new String[] {PERMISSION_RECORD_AUDIO};
  }

  private boolean hasPermissions(String[] permissions) {
    for (String permission : permissions) {
      if (!hasPermission(permission)) {
        return false;
      }
    }
    return true;
  }

  private boolean hasPermission(String permission) {
    return Build.VERSION.SDK_INT < Build.VERSION_CODES.M
        || checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED;
  }

  private Map<String, Object> mediaPermissionResult(boolean requireVideo) {
    final Map<String, Object> result = new HashMap<>();
    final boolean microphoneGranted = hasPermission(PERMISSION_RECORD_AUDIO);
    final boolean cameraGranted = !requireVideo || hasPermission(PERMISSION_CAMERA);
    result.put("microphoneGranted", microphoneGranted);
    result.put("cameraGranted", cameraGranted);
    result.put("granted", microphoneGranted && cameraGranted);
    return result;
  }

  @Override
  public void onRequestPermissionsResult(
      int requestCode, String[] permissions, int[] grantResults) {
    if (requestCode != MEDIA_PERMISSION_REQUEST_CODE) {
      super.onRequestPermissionsResult(requestCode, permissions, grantResults);
      return;
    }

    final MethodChannel.Result result = pendingMediaPermissionResult;
    pendingMediaPermissionResult = null;
    if (result == null) {
      return;
    }

    result.success(mediaPermissionResult(includesCameraPermission(permissions)));
  }

  private boolean includesCameraPermission(String[] permissions) {
    for (String permission : permissions) {
      if (PERMISSION_CAMERA.equals(permission)) {
        return true;
      }
    }
    return false;
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
