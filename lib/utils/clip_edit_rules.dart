import '../data/models.dart';
import 'clip_range.dart';

/// Pure form rules for the clip editor, kept free of Flutter and Media Kit so
/// they can be unit tested.

/// Builds the clip that would be persisted from the current form state.
///
/// Mirrors the editor's save normalisation: the name is trimmed (empty becomes
/// `Untitled Clip`) and empty notes become `null`. A new [VideoClip] is built
/// directly because `copyWith` cannot clear `notes`.
VideoClip composeClip(
  VideoClip form, {
  required String name,
  required String notes,
}) {
  final trimmedName = name.trim();
  final trimmedNotes = notes.trim();
  return VideoClip(
    id: form.id,
    name: trimmedName.isEmpty ? 'Untitled Clip' : trimmedName,
    videoPath: form.videoPath,
    startTime: form.startTime,
    endTime: form.endTime,
    coverFrameTime: form.coverFrameTime,
    tags: form.tags,
    notes: trimmedNotes.isEmpty ? null : trimmedNotes,
    rating: form.rating,
    isFavorite: form.isFavorite,
    thumbnailPath: form.thumbnailPath,
    aiSummary: form.aiSummary,
    aiScene: form.aiScene,
    aiActions: form.aiActions,
    hitTimestampMs: form.hitTimestampMs,
  );
}

/// Whether [composed] differs from what [baseline] would save as. The
/// baseline is normalised the same way so an untouched form is never dirty.
bool isClipDirty(VideoClip composed, VideoClip baseline) {
  final normalizedBaseline = composeClip(
    baseline,
    name: baseline.name,
    notes: baseline.notes ?? '',
  );
  return composed != normalizedBaseline;
}

/// Returns why [clip] must not be saved, or `null` when saving is allowed.
///
/// The IN/OUT upper bound against [source] is only enforced when the range was
/// actually changed relative to [original]; this keeps tag or note edits on a
/// legacy clip whose stored OUT slightly exceeds the probed duration possible.
/// `end > start` is always required.
String? validateClipForSave(
  VideoClip clip, {
  VideoClip? original,
  required Duration source,
}) {
  final rangeUnchanged =
      original != null &&
      original.startTime == clip.startTime &&
      original.endTime == clip.endTime;
  final error = ClipRangeRules.validate(
    clip.startTime,
    clip.endTime,
    rangeUnchanged ? Duration.zero : source,
  );
  return error == null
      ? null
      : ClipRangeRules.message(error, sourceDuration: source);
}
