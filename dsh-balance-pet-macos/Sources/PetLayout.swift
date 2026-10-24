import AppKit

/// Which bottom corner the pet is parked in. The pet faces the middle of the
/// screen either way: parked on the right it is drawn mirrored.
enum PetSide {
    case left, right
}

/// Pressing the pet ducks its head: the artwork briefly loses a tenth of its
/// height, anchored on its feet, then springs back. Kept as pure timing so the
/// shape of the motion can be checked without a window server.
enum PetDuck {
    /// Total length of the squash and its recovery.
    static let duration: CFTimeInterval = 0.24
    /// Height lost at the deepest point, as a fraction of the artwork height.
    static let squash: CGFloat = 0.10
    /// When the squash bottoms out, as a fraction of `duration`. The head drops
    /// faster than it comes back up.
    static let bottom: Double = 0.32

    /// Vertical scale at `elapsed` seconds after the press.
    static func scale(after elapsed: CFTimeInterval) -> CGFloat {
        guard elapsed > 0, elapsed < duration else { return 1 }
        let progress = elapsed / duration
        let depth = progress < bottom ? progress / bottom
                                      : 1 - (progress - bottom) / (1 - bottom)
        return 1 - squash * CGFloat(max(0, min(1, depth)))
    }

    /// The artwork rect shortened about its bottom edge, so the feet stay put.
    static func rect(_ rect: CGRect, after elapsed: CFTimeInterval) -> CGRect {
        let scale = scale(after: elapsed)
        guard scale < 1 else { return rect }
        return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * scale)
    }
}

/// Layout of a character's artwork inside its window. A size preset means body
/// height, so switching between the 1:1 expression set and the 3:2 artwork set
/// keeps the pet the same height instead of the same width.
enum PetLayout {
    static let floatBand: CGFloat = 0.55
    static let tabletBounds = CGRect(x: 0, y: 0, width: 400, height: 220)

    static func windowSize(side: CGFloat, character: PetCharacter) -> CGSize {
        CGSize(width: side * character.aspectRatio, height: side * (1 + floatBand))
    }

    static func bodyHeight(in bounds: CGRect, character: PetCharacter) -> CGFloat {
        bounds.width / character.aspectRatio
    }

    static func spriteRect(in bounds: CGRect, character: PetCharacter) -> CGRect {
        let side = bodyHeight(in: bounds, character: character)
        let size = CGSize(width: side * 0.94 * character.aspectRatio, height: side * 0.94)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.minY + side * 0.03,
                      width: size.width, height: size.height)
    }

    /// Space between the window's bottom edge and the lowest drawn pixel. The
    /// window keeps a floating band above the pet, so its frame reaches further
    /// down than the artwork; snapping subtracts this to make the pet itself
    /// touch the edge of the screen.
    static func artworkBottomInset(in bounds: CGRect, character: PetCharacter) -> CGFloat {
        spriteRect(in: bounds, character: character).minY - bounds.minY
    }

    /// Space between the window's side edge and the drawn artwork. The art is
    /// inset by 3% on each side, so a window flush with the screen edge still
    /// floats; snapping compensates with this value on both corners.
    static func artworkHorizontalInset(in bounds: CGRect, character: PetCharacter) -> CGFloat {
        (bounds.width - spriteRect(in: bounds, character: character).width) / 2
    }

    /// The corner the pet belongs to, given where its window currently sits.
    /// Crossing the middle of the screen hands it to the other corner.
    static func side(forWindowMidX midX: CGFloat, in visibleFrame: CGRect) -> PetSide {
        midX > visibleFrame.midX ? .right : .left
    }

    /// Window origin that parks the artwork in `side`'s bottom corner: the
    /// lowest and outermost drawn pixels touch the screen edge, so the window
    /// frame deliberately overhangs the visible frame by its artwork insets.
    static func cornerOrigin(side: PetSide,
                             in visibleFrame: CGRect,
                             windowSize: CGSize,
                             character: PetCharacter) -> CGPoint {
        let local = CGRect(origin: .zero, size: windowSize)
        let horizontal = artworkHorizontalInset(in: local, character: character)
        let vertical = artworkBottomInset(in: local, character: character)
        let x = side == .left ? visibleFrame.minX - horizontal
                              : visibleFrame.maxX - windowSize.width + horizontal
        return CGPoint(x: x, y: visibleFrame.minY - vertical)
    }

    /// Aspect-preserving, bottom-aligned draw rect. Used when the artwork's own
    /// aspect differs from the character's canvas, such as the 3:2 offline bowl
    /// on the square expression canvas.
    static func contentRect(for artwork: CGSize, in rect: CGRect) -> CGRect {
        guard artwork.width > 0, artwork.height > 0, rect.width > 0, rect.height > 0 else { return rect }
        let scale = min(rect.width / artwork.width, rect.height / artwork.height)
        let fitted = CGSize(width: artwork.width * scale, height: artwork.height * scale)
        return CGRect(x: rect.midX - fitted.width / 2, y: rect.minY,
                      width: fitted.width, height: fitted.height)
    }

    static func tabletTransform(in bounds: CGRect,
                                character: PetCharacter,
                                expression: PetExpression = .happy,
                                mirrored: Bool = false) -> CGAffineTransform {
        // Convert the selected image's measured corners to bottom-origin source
        // coordinates, using the exact same scale as its sprite and alpha mask.
        // A mirrored pet flips the artwork, so the panel's own corners swap and
        // the fourth corner is mirrored too; the text is mapped upright into the
        // mirrored screen instead of being mirrored with the pixels.
        var corners = character.tabletCorners(for: expression)
        if mirrored {
            let measured = corners
            let width = character.artworkSize.width
            let bottomRight = CGPoint(x: measured.topRight.x + measured.bottomLeft.x - measured.topLeft.x,
                                      y: measured.topRight.y + measured.bottomLeft.y - measured.topLeft.y)
            corners = (topLeft: CGPoint(x: width - measured.topRight.x, y: measured.topRight.y),
                       topRight: CGPoint(x: width - measured.topLeft.x, y: measured.topLeft.y),
                       bottomLeft: CGPoint(x: width - bottomRight.x, y: bottomRight.y))
        }
        let rect = spriteRect(in: bounds, character: character)
        let artwork = character.artworkSize
        let scale = rect.width / artwork.width
        return CGAffineTransform(a: (corners.topRight.x - corners.topLeft.x) / tabletBounds.width * scale,
                                 b: (corners.topLeft.y - corners.topRight.y) / tabletBounds.width * scale,
                                 c: (corners.topLeft.x - corners.bottomLeft.x) / tabletBounds.height * scale,
                                 d: (corners.bottomLeft.y - corners.topLeft.y) / tabletBounds.height * scale,
                                 tx: rect.minX + corners.bottomLeft.x * scale,
                                 ty: rect.minY + (artwork.height - corners.bottomLeft.y) * scale)
    }
}
