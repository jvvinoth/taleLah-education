/// Community event — language-based SG kids programmes from the
/// Community Scout agent (GET /events).
class CommunityEvent {
  final String id;
  final String title;
  final String description;
  final String language; // ta / zh / ms / en
  final String date; // ISO yyyy-mm-dd
  final String time;
  final String venue;
  final String ageRange;
  final String organizer;
  final String registrationUrl;
  final bool isFree;

  CommunityEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.language,
    required this.date,
    required this.time,
    required this.venue,
    required this.ageRange,
    required this.organizer,
    required this.registrationUrl,
    required this.isFree,
  });

  factory CommunityEvent.fromJson(Map<String, dynamic> json) => CommunityEvent(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        language: json['language'] as String? ?? 'en',
        date: json['date'] as String? ?? '',
        time: json['time'] as String? ?? '',
        venue: json['venue'] as String? ?? '',
        ageRange: json['age_range'] as String? ?? '',
        organizer: json['organizer'] as String? ?? '',
        registrationUrl: json['registration_url'] as String? ?? '',
        isFree: json['is_free'] as bool? ?? true,
      );
}
