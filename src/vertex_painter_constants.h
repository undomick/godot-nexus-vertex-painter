#ifndef VERTEX_PAINTER_CONSTANTS_H
#define VERTEX_PAINTER_CONSTANTS_H

/// Version and author (override at build time via SCons: addon_version=, addon_author=).
#ifndef NEXUS_VERTEX_PAINTER_VERSION
#define NEXUS_VERTEX_PAINTER_VERSION "2.3.1"
#endif
#ifndef NEXUS_VERTEX_PAINTER_AUTHOR
#define NEXUS_VERTEX_PAINTER_AUTHOR "Michael Kulzer"
#endif

namespace vertex_painter {

constexpr const char *kVersion = NEXUS_VERTEX_PAINTER_VERSION;
constexpr const char *kAuthor = NEXUS_VERTEX_PAINTER_AUTHOR;

} // namespace vertex_painter

#endif // VERTEX_PAINTER_CONSTANTS_H
