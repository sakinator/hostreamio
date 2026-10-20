import 'package:flutter/material.dart';
import 'tv_focusable_button.dart';

/// Modular, TV-friendly Catalog Browser Widget.
/// Manages catalogue tabs (Trending Movies, Series, Hindi, Asian Dramas, YouTube, IPTV),
/// genre filter chips, uniform sort dropdown, and the media poster grid.
class CatalogBrowserWidget extends StatelessWidget {
  final Map<String, Map<String, dynamic>> catalogDefs;
  final String activeCatalogTab;
  final String activeCatalogGenre;
  final String catalogSortFilter;
  final List<Map<String, dynamic>> catalogItems;
  final bool isLoadingCatalog;
  final bool isWide;
  final ValueChanged<String> onTabChanged;
  final ValueChanged<String> onGenreChanged;
  final ValueChanged<String> onSortChanged;
  final ValueChanged<Map<String, dynamic>> onItemTap;
  final VoidCallback onLoadMore;

  const CatalogBrowserWidget({
    super.key,
    required this.catalogDefs,
    required this.activeCatalogTab,
    required this.activeCatalogGenre,
    required this.catalogSortFilter,
    required this.catalogItems,
    required this.isLoadingCatalog,
    this.isWide = false,
    required this.onTabChanged,
    required this.onGenreChanged,
    required this.onSortChanged,
    required this.onItemTap,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final currentDef = catalogDefs[activeCatalogTab];
    final genres = currentDef != null && currentDef.containsKey('genres')
        ? currentDef['genres'] as List<String>?
        : null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF11141C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1F2432), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              const Icon(Icons.video_library_rounded, color: Color(0xFFFF0C82), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Browse Catalogs',
                  style: TextStyle(
                    fontSize: isWide ? 18 : 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              // Sort Filter Dropdown (Uniform across all catalogs)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF090D13),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1F2432)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: catalogSortFilter,
                    dropdownColor: const Color(0xFF161B26),
                    icon: const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.tune_rounded, size: 16, color: Color(0xFFFF0C82)),
                    ),
                    isDense: true,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'new', child: Text('✨ New Digital Releases')),
                      DropdownMenuItem(value: 'trending', child: Text('🔥 Trending Now')),
                      DropdownMenuItem(value: 'popular', child: Text('⭐ Most Popular')),
                      DropdownMenuItem(value: 'top_rated', child: Text('🏆 Top Rated')),
                    ],
                    onChanged: (val) {
                      if (val != null && val != catalogSortFilter) {
                        onSortChanged(val);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Catalog Tabs Row
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: catalogDefs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final key = catalogDefs.keys.elementAt(index);
                final def = catalogDefs[key]!;
                final isActive = (key == activeCatalogTab);
                final label = def['label'] as String;

                return TvFocusableButton(
                  onPressed: () {
                    if (activeCatalogTab != key) {
                      onTabChanged(key);
                    }
                  },
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
                      label,
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

          // Genre Filter Chips Row (if applicable)
          if (genres != null && genres.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: genres.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final g = genres[index];
                  final isActive = (g == activeCatalogGenre);
                  return GestureDetector(
                    onTap: () {
                      if (activeCatalogGenre != g) {
                        onGenreChanged(g);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFFFF0C82) : const Color(0xFF141923),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isActive ? const Color(0xFFFF0C82) : const Color(0xFF2A3142),
                        ),
                      ),
                      child: Text(
                        g,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          color: isActive ? Colors.white : Colors.grey.shade300,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 14),

          // Media Items Grid
          if (catalogItems.isEmpty && isLoadingCatalog)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(color: Color(0xFF195FEB)),
              ),
            )
          else if (catalogItems.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text(
                  'No titles found in this catalogue filter.',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ),
            )
          else ...[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isWide ? 6 : 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
                childAspectRatio: 0.65,
              ),
              itemCount: catalogItems.length,
              itemBuilder: (context, index) {
                final item = catalogItems[index];
                final name = item['name']?.toString() ?? 'Unknown';
                final poster = item['poster']?.toString() ?? item['background']?.toString() ?? '';
                final rating = item['rating']?.toString() ?? item['imdbRating']?.toString();
                final year = item['year']?.toString();

                return TvFocusableButton(
                  onPressed: () => onItemTap(item),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B26),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF222938)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (poster.isNotEmpty)
                          Image.network(
                            poster,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: const Color(0xFF1A1F2C),
                              child: const Icon(Icons.movie_rounded, color: Colors.grey),
                            ),
                          )
                        else
                          Container(
                            color: const Color(0xFF1A1F2C),
                            child: const Icon(Icons.movie_rounded, color: Colors.grey),
                          ),

                        // Gradient shadow overlay
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.1),
                                  Colors.black.withOpacity(0.85),
                                ],
                                stops: const [0.5, 0.7, 1.0],
                              ),
                            ),
                          ),
                        ),

                        // Rating badge
                        if (rating != null && rating.isNotEmpty && rating != '0.0')
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.75),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFE5A00D), width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded, size: 10, color: Color(0xFFE5A00D)),
                                  const SizedBox(width: 2),
                                  Text(
                                    rating,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Bottom Title & Year
                        Positioned(
                          left: 6,
                          right: 6,
                          bottom: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  height: 1.15,
                                ),
                              ),
                              if (year != null && year.isNotEmpty)
                                Text(
                                  year,
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            // Load More button
            const SizedBox(height: 14),
            Center(
              child: TvFocusableButton(
                onPressed: isLoadingCatalog ? null : onLoadMore,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B26),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF2C3448)),
                  ),
                  child: isLoadingCatalog
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          '⬇️ Load More Titles',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
