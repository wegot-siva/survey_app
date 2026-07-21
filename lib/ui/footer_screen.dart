import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/survey_repository.dart';
import '../models/footer.dart';
import '../models/site.dart';
import '../models/survey_photo.dart';
import 'photo_markup_screen.dart';
import 'widgets/form_fields.dart';
import 'widgets/photo_capture_field.dart';

/// The per-site "Footer" form — closing, site-wide details. One per site (like
/// Client inputs). Surveyor name and survey date are mandatory (see
/// `_save`); every other field is optional (partial saves).
class FooterScreen extends StatefulWidget {
  const FooterScreen({
    super.key,
    required this.repository,
    required this.site,
    this.readOnly = false,
    this.isAdmin = false,
  });

  final SurveyRepository repository;
  final Site site;
  final bool readOnly;

  /// Shows the Admin-only "Fill test data" shortcut — a dev/QA tool that
  /// fills every mandatory field with a placeholder value so the section
  /// passes validation instantly. Never shown to any other role.
  final bool isAdmin;

  @override
  State<FooterScreen> createState() => _FooterScreenState();
}

class _FooterScreenState extends State<FooterScreen> {
  final TextEditingController _tds = TextEditingController();
  final TextEditingController _tss = TextEditingController();
  final TextEditingController _tclServiceDetails = TextEditingController();
  final TextEditingController _generalRemarks = TextEditingController();
  final TextEditingController _surveyorName = TextEditingController();

  bool? _tclService;
  DateTime? _surveyDate;

  /// Site photos/videos — multiple allowed. Loaded with the footer; reconciled
  /// on save (ordered by list position).
  final List<PhotoDraft> _sitePhotos = [];

  bool _loading = true;
  bool _saving = false;

  // Mandatory-field errors, set on a failed save attempt and cleared on the
  // next one — see _save().
  String? _surveyorNameError;
  bool _surveyDateError = false;
  String? _tdsError;
  String? _tssError;
  String? _tclServiceError;
  String? _tclServiceDetailsError;

  /// Starts false; flips true when the Edit button is tapped. Irrelevant
  /// unless [widget.readOnly] — see [_viewOnly].
  bool _editing = false;

  /// True while fields should be visible but non-interactive: opened
  /// read-only (Approver review) and Edit hasn't been tapped yet. Gates an
  /// [IgnorePointer], not each field's `enabled` — so the fields keep their
  /// normal (not greyed-out) styling in view mode.
  bool get _viewOnly => widget.readOnly && !_editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final existing = await widget.repository.getFooter(widget.site.id);
    final photos = await widget.repository.getPhotos(
      PhotoOwner.footer,
      widget.site.id,
    );
    if (!mounted) return;
    setState(() {
      if (existing != null) {
        _tds.text = existing.tdsPpm?.toString() ?? '';
        _tss.text = existing.tssPpm?.toString() ?? '';
        _tclServiceDetails.text = existing.tclServiceDetails;
        _generalRemarks.text = existing.generalRemarks;
        _surveyorName.text = existing.surveyorName;
        _tclService = existing.tclService;
        _surveyDate = existing.surveyDate;
      }
      for (final p in photos) {
        if (p.slot == PhotoSlot.siteMedia) {
          _sitePhotos.add(
            PhotoDraft(
              id: p.id,
              localPath: p.localPath,
              remotePath: p.remotePath,
            ),
          );
        }
      }
      _loading = false;
    });
  }

  void _onPhotoAdded(String localPath) {
    setState(() => _sitePhotos.add(PhotoDraft(localPath: localPath)));
  }

  void _onPhotoRemoved(int index) {
    setState(() => _sitePhotos.removeAt(index));
  }

  /// Opens the markup screen for an existing photo. The photo keeps its id
  /// (so saving updates the same record/Storage object instead of creating an
  /// orphan); only its local path changes, and remotePath resets to null so
  /// the marked-up version is re-uploaded on the next sync.
  Future<void> _onPhotoEdit(int index) async {
    final draft = _sitePhotos[index];
    final path = draft.localPath;
    if (path == null) return;

    final newPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => PhotoMarkupScreen(imagePath: path)),
    );
    if (newPath == null || !mounted) return;
    setState(() {
      draft.localPath = newPath;
      draft.remotePath = null;
    });
  }

  /// Read-only counterpart to [_onPhotoEdit] — opens the photo full-screen
  /// with no markup/edit capability. Used when the form is view-only.
  Future<void> _onPhotoView(int index) async {
    final path = _sitePhotos[index].localPath;
    if (path == null) return;
    await openPhotoViewer(context, path, title: 'Site photo');
  }

  List<SurveyPhoto> _photoList() {
    final list = <SurveyPhoto>[];
    for (var i = 0; i < _sitePhotos.length; i++) {
      final draft = _sitePhotos[i];
      if (draft.localPath == null) continue;
      list.add(
        SurveyPhoto(
          id: draft.id,
          ownerType: PhotoOwner.footer,
          ownerId: widget.site.id,
          slot: PhotoSlot.siteMedia,
          position: i,
          localPath: draft.localPath,
          remotePath: draft.remotePath,
          siteId: widget.site.id,
        ),
      );
    }
    return list;
  }

  @override
  void dispose() {
    _tds.dispose();
    _tss.dispose();
    _tclServiceDetails.dispose();
    _generalRemarks.dispose();
    _surveyorName.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _surveyDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _surveyDate = picked);
  }

  /// Admin-only dev/QA shortcut — fills every mandatory field with a
  /// placeholder value so the section passes validation immediately.
  void _fillTestData() {
    setState(() {
      _tds.text = '1';
      _tss.text = '1';
      _tclService = false;
      _surveyorName.text = 'Test Surveyor';
      _surveyDate = DateTime.now();
      _surveyorNameError = null;
      _surveyDateError = false;
      _tdsError = null;
      _tssError = null;
      _tclServiceError = null;
      _tclServiceDetailsError = null;
    });
  }

  Future<void> _save() async {
    final surveyorName = _surveyorName.text.trim();
    final tds = _tds.text.trim();
    final tss = _tss.text.trim();
    final tclServiceDetails = _tclServiceDetails.text.trim();

    setState(() {
      _surveyorNameError = surveyorName.isEmpty ? 'Required' : null;
      _surveyDateError = _surveyDate == null;
      _tdsError = tds.isEmpty ? 'Required' : null;
      _tssError = tss.isEmpty ? 'Required' : null;
      _tclServiceError = _tclService == null ? 'Required' : null;
      _tclServiceDetailsError =
          (_tclService == true && tclServiceDetails.isEmpty)
          ? 'Required'
          : null;
    });
    if (_surveyorNameError != null ||
        _surveyDateError ||
        _tdsError != null ||
        _tssError != null ||
        _tclServiceError != null ||
        _tclServiceDetailsError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in the required fields.')),
      );
      return;
    }

    setState(() => _saving = true);

    final footer = Footer(
      tdsPpm: double.tryParse(_tds.text.trim()),
      tssPpm: double.tryParse(_tss.text.trim()),
      tclService: _tclService,
      tclServiceDetails: _tclService == true
          ? _tclServiceDetails.text.trim()
          : '',
      generalRemarks: _generalRemarks.text.trim(),
      surveyDate: _surveyDate,
      surveyorName: surveyorName,
    );

    await widget.repository.saveFooter(widget.site.id, footer);
    await widget.repository.setPhotos(
      PhotoOwner.footer,
      widget.site.id,
      _photoList(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Footer saved.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _surveyDate == null
        ? 'Survey date — not set'
        : 'Survey date: ${_surveyDate!.toIso8601String().split('T').first}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Footer'),
        actions: [
          if (widget.isAdmin && !_viewOnly)
            IconButton(
              tooltip: 'Fill test data (Admin only)',
              onPressed: _fillTestData,
              icon: const Icon(Icons.auto_fix_high),
            ),
          if (_viewOnly)
            IconButton(
              tooltip: 'Edit',
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                IgnorePointer(
                  ignoring: _viewOnly,
                  child: Column(
                    children: [
                      AppTextField(
                        controller: _tds,
                        label: 'TDS (ppm) *',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        errorText: _tdsError,
                      ),
                      AppTextField(
                        controller: _tss,
                        label: 'TSS (ppm) *',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        errorText: _tssError,
                      ),
                      YesNoField(
                        label: 'TCL service *',
                        value: _tclService,
                        onChanged: (v) => setState(() => _tclService = v),
                        errorText: _tclServiceError,
                      ),
                      if (_tclService == true)
                        AppTextField(
                          controller: _tclServiceDetails,
                          label: 'TCL service details *',
                          maxLines: 2,
                          errorText: _tclServiceDetailsError,
                        ),
                      AppTextField(
                        controller: _generalRemarks,
                        label: 'General remarks',
                        maxLines: 3,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: OutlinedButton.icon(
                          onPressed: _pickDate,
                          style: _surveyDateError
                              ? OutlinedButton.styleFrom(
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.error,
                                  side: BorderSide(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                )
                              : null,
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('$dateLabel *'),
                          ),
                        ),
                      ),
                      if (_surveyDateError)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Required',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                          ),
                        )
                      else
                        const SizedBox(height: 12),
                      AppTextField(
                        controller: _surveyorName,
                        label: 'Surveyor name *',
                        errorText: _surveyorNameError,
                      ),
                    ],
                  ),
                ),

                const FormSectionLabel('Photos / videos'),
                MultiPhotoCaptureField(
                  label: 'Site photos / videos',
                  photos: [
                    for (final p in _sitePhotos)
                      if (p.localPath != null)
                        PhotoView(p.localPath!, uploaded: p.uploaded),
                  ],
                  onAdded: _onPhotoAdded,
                  onRemoved: _onPhotoRemoved,
                  onEdit: _viewOnly ? null : _onPhotoEdit,
                  onView: _onPhotoView,
                  readOnly: _viewOnly,
                ),

                if (!_viewOnly) ...[
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save footer'),
                  ),
                ],
              ],
            ),
    );
  }
}
