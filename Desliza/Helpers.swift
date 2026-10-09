import Foundation

/// "1,2 GB", "350 MB"...
func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

/// "Marzo de 2025"
func monthTitle(year: Int, month: Int) -> String {
    guard let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) else {
        return "\(month)/\(year)"
    }
    let text = date.formatted(.dateTime.month(.wide).year())
    return text.prefix(1).uppercased() + text.dropFirst()
}

/// Categorías de limpieza.
enum CleanCategory {
    case recent
    case random
    case onThisDay
    case screenshots
    case videos
    case largeVideos
    case month(year: Int, month: Int)

    var title: String {
        switch self {
        case .recent: return "Recientes"
        case .random: return "Aleatorias"
        case .onThisDay: return "Este día"
        case .screenshots: return "Capturas de pantalla"
        case .videos: return "Vídeos"
        case .largeVideos: return "Vídeos más pesados"
        case .month(let year, let month): return monthTitle(year: year, month: month)
        }
    }

    var subtitle: String {
        switch self {
        case .recent: return "De la más nueva a la más antigua"
        case .random: return "Tandas de 30 al azar"
        case .onThisDay: return "Lo que hiciste tal día como hoy"
        case .screenshots: return "Suelen sobrar casi todas"
        case .videos: return "Los que más ocupan"
        case .largeVideos: return "Ordenados por tamaño, de mayor a menor"
        case .month: return ""
        }
    }

    var systemImage: String {
        switch self {
        case .recent: return "clock"
        case .random: return "shuffle"
        case .onThisDay: return "calendar.badge.clock"
        case .screenshots: return "camera.viewfinder"
        case .videos: return "video"
        case .largeVideos: return "externaldrive.fill"
        case .month: return "calendar"
        }
    }

    var isRandom: Bool {
        if case .random = self { return true }
        return false
    }
}

enum SwipeAction {
    case keep(String)
    case trash(String)
}
