import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum TipoImagem { produtos, logo }

/// Escolhe uma foto (galeria ou câmera), reduz e envia para o Storage.
/// Caminho {id_empresa}/{produtos|logo}/{tempo}.jpg — a policy do bucket exige a pasta = id da loja.
class ImagemServico {
  ImagemServico._();
  static final instancia = ImagemServico._();

  final _seletor = ImagePicker();

  /// Retorna a URL pública ou null se o lojista cancelar
  Future<String?> escolherEEnviar({
    required int idEmpresa,
    required TipoImagem tipo,
    ImageSource origem = ImageSource.gallery,
  }) async {
    final lado = tipo == TipoImagem.logo ? 400.0 : 800.0;
    final foto = await _seletor.pickImage(source: origem, maxWidth: lado, maxHeight: lado, imageQuality: 82);
    if (foto == null) return null;

    final bytes = await foto.readAsBytes();
    final caminho = '$idEmpresa/${tipo.name}/${DateTime.now().microsecondsSinceEpoch}.jpg';
    final storage = Supabase.instance.client.storage.from('imagens');
    await storage.uploadBinary(
      caminho,
      bytes,
      fileOptions: const FileOptions(contentType: 'image/jpeg', cacheControl: '31536000'),
    );
    return storage.getPublicUrl(caminho);
  }
}
