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

    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(path, fit: BoxFit.cover),
      ),
    );
  }
}
