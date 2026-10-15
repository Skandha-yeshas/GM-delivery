import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

abstract class BillScanService {
  Future<String?> pick(ImageSource source);
  Future<String?> recoverLostImage();
  Future<String> readText(String path);
}

class DeviceBillScanService implements BillScanService {
  @override
  Future<String?> pick(ImageSource source) async =>
      (await ImagePicker().pickImage(
        source: source,
        maxWidth: 2600,
        imageQuality: 95,
      ))?.path;

  @override
  Future<String?> recoverLostImage() async {
    final response = await ImagePicker().retrieveLostData();
    if (response.exception != null) throw response.exception!;
    return response.files?.firstOrNull?.path;
  }

  @override
  Future<String> readText(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      return (await recognizer.processImage(
        InputImage.fromFilePath(path),
      )).text;
    } finally {
      await recognizer.close();
    }
  }
}
