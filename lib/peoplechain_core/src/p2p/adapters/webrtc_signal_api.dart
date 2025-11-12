abstract class WebRtcSignalApi {
  Future<String> createOfferPayload();
  Future<String> acceptOfferAndCreateAnswer(String base64OfferPayload);
  Future<void> acceptAnswer(String base64AnswerPayload);
}
