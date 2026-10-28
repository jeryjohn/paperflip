/// A realistic book page-flip widget for Flutter.
///
/// Features realistic 3D mesh page-curl animation with physical lighting,
/// dynamic shadows, drag-to-curl physics, programmatic control, PDF rendering,
/// reflowable EPUB support, and arbitrary widget page content.
library paperflip;

export 'src/epub/epub_controller.dart';
export 'src/epub/epub_document.dart';
export 'src/epub/epub_pagination.dart';
export 'src/epub/epub_reader_settings.dart';
export 'src/epub/epub_renderer.dart';
export 'src/epub/epub_source.dart';
export 'src/epub/paperflip_epub.dart';
export 'src/paperflip.dart';
export 'src/paperflip_controller.dart';
export 'src/flip_corner.dart';
export 'src/flip_settings.dart';
export 'src/paperflip_pdf.dart';
export 'src/paperflip_reader.dart';
export 'src/mesh_paperflip.dart';
export 'src/page_builder.dart';
export 'src/page_selector_dialog.dart';
export 'src/volume/volume_key_manager.dart';
// Required by Flutter's generated Dart plugin registrant for Windows.
// This implementation intentionally registers no native event channel.
export 'src/platform/paperflip_noop_plugin.dart' show PaperflipNoopPlugin;
export 'package:pdfrx/pdfrx.dart';
