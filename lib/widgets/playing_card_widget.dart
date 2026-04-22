import 'package:flutter/material.dart';

class PlayingCardWidget extends StatelessWidget {
  final String cardId;
  final bool faceDown;
  final double width;
  final double height;

  const PlayingCardWidget({
    super.key,
    required this.cardId,
    this.faceDown = false,
    this.width = 90,
    this.height = 135,
  });

  @override
  Widget build(BuildContext context) {
    final path = faceDown
        ? 'assets/cards/back.png'
        : 'assets/cards/$cardId.png';

    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            path,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return Container(
                color: Colors.white,
                alignment: Alignment.center,
                child: Text(
                  faceDown ? 'BACK' : cardId,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}