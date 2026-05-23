import 'voice_media_models.dart';

abstract class VoiceMediaConnection {
  Stream<VoiceIceCandidate> get onIceCandidate;
  Stream<VoiceRemoteAudioTrack> get onRemoteAudioTrack;
  Stream<VoiceMediaState> get onStateChanged;

  Future<void> startLocalAudio();
  Future<VoiceSessionDescription> createOffer();
  Future<VoiceSessionDescription> acceptOffer(VoiceSessionDescription offer);
  Future<void> applyAnswer(VoiceSessionDescription answer);
  Future<void> addRemoteCandidate(VoiceIceCandidate candidate);
  Future<void> setMuted({required bool muted});
  Future<void> dispose();
}
