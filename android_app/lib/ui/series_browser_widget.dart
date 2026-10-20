import 'package:flutter/material.dart';
import 'tv_focusable_button.dart';

/// Modular, TV Remote-compatible Seasons and Episodes catalog browser.
/// Displays seasons as a horizontal pill bar, followed by a responsive list
/// of episode cards featuring still previews, multi-line synopses, and play triggers.
class SeriesBrowserWidget extends StatelessWidget {
  final Map<String, dynamic> seriesDetails;
  final int selectedSeason;
  final String? selectedEpisodeId;
  final ValueChanged<int> onSeasonChanged;
  final void Function(Map<String, dynamic> episode, String formattedEpId) onEpisodeTap;

  const SeriesBrowserWidget({
    super.key,
    required this.seriesDetails,
    required this.selectedSeason,
    required this.selectedEpisodeId,
    required this.onSeasonChanged,
    required this.onEpisodeTap,
  });

  @override
  Widget build(BuildContext context) {
    final seasons = (seriesDetails['seasons'] as List?)
            ?.map((e) => int.tryParse(e.toString()) ?? 1)
            .toList() ??
        [1];
    final epsBySeason = (seriesDetails['episodesBySeason'] as Map<String, dynamic>?) ?? {};
    final currentEps = (epsBySeason['$selectedSeason'] as List?) ?? [];
    final seriesName = seriesDetails['name']?.toString() ?? 'Series';
    final fallbackPoster = seriesDetails['poster']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11141C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1F2432)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '📺 Seasons & Episodes ($seriesName)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${seasons.length} Season(s)',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Seasons Horizontal Bar
          if (seasons.length > 1) ...[
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: seasons.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final sNum = seasons[index];
                  final isActive = (sNum == selectedSeason);
                  return TvFocusableButton(
                    isPrimary: isActive,
                    onPressed: () => onSeasonChanged(sNum),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFF195FEB) : const Color(0xFF090D13),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isActive ? const Color(0xFF195FEB) : const Color(0xFF1F2432),
                        ),
                      ),
                      child: Text(
                        'Season $sNum',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isActive ? Colors.white : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Episodes List
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: currentEps.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final ep = currentEps[index] as Map<String, dynamic>;
                final epId = ep['id']?.toString() ?? '';
                final isSelected = (epId == selectedEpisodeId);
                final thumb = ep['thumbnail']?.toString() ?? fallbackPoster;
                final epNumStr = 'S${ep['season'] < 10 ? '0' : ''}${ep['season']}E${ep['episode'] < 10 ? '0' : ''}${ep['episode']}';
                final epTitle = ep['name']?.toString() ?? 'Episode ${ep['episode']}';
                final overview = ep['overview']?.toString();

                return TvFocusableButton(
                  isPrimary: isSelected,
                  primaryColor: const Color(0xFF195FEB),
                  onPressed: () => onEpisodeTap(ep, epNumStr),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF195FEB).withOpacity(0.18)
                          : const Color(0xFF090D13),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF195FEB) : const Color(0xFF1F2432),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (thumb.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              thumb,
                              width: 70,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 70,
                                height: 52,
                                color: const Color(0xFF1A1F2C),
                                child: const Icon(Icons.movie_rounded, size: 20, color: Colors.grey),
                              ),
                            ),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$epNumStr: $epTitle',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (overview != null && overview.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    overview,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade400,
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.play_circle_outline_rounded,
                          color: Color(0xFFFF0C82),
                          size: 26,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
