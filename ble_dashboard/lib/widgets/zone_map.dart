import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ZoneMap extends StatefulWidget {
  final List<dynamic> activePatients;
  final Function(String zoneName, String? gatewayId) onZoneTap;

  const ZoneMap({
    Key? key, 
    this.activePatients = const [],
    required this.onZoneTap,
  }) : super(key: key);

  @override
  State<ZoneMap> createState() => _ZoneMapState();
}

class _ZoneMapState extends State<ZoneMap> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine the space available. We'll no longer force AspectRatio
    // so it can expand fluidly, just use the constraints directly.
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117), // very dark background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      padding: const EdgeInsets.all(8.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          return Stack(
            children: [
              // === STAIRCASE (LEFT SIDE L-SHAPE) ===
              _buildBlock(
                left: 0.0, top: 0.0, width: w * 0.38, height: h * 0.15,
                color: Colors.grey.shade800,
                zoneName: '',
                roomName: 'Shaft',
                isEmpty: true,
              ),
              _buildBlock(
                left: 0.0, top: h * 0.15, width: w * 0.38, height: h * 0.13,
                color: Colors.blueGrey.shade800,
                zoneName: 'Staircase',
                roomName: '',
              ),
              _buildBlock(
                left: 0.0, top: h * 0.28, width: w * 0.15, height: h * 0.27,
                color: Colors.blueGrey.shade800,
                zoneName: 'Staircase',
                roomName: '',
              ),

              // === HOSPITAL ZONES ===
              
              // Operation Theater (Bathroom previously) - Teal
              _buildBlock(
                left: w * 0.38, top: 0.0, width: w * 0.42, height: h * 0.28,
                color: const Color(0xFF00BFA5),
                zoneName: 'Operation Theater',
                roomName: 'Bathroom',
                gatewayId: 'GW_003',
              ),

              // OPD Waiting (Entrance) - Purple
              _buildBlock(
                left: w * 0.80, top: 0.0, width: w * 0.20, height: h * 0.28,
                color: const Color(0xFF7C4DFF),
                zoneName: 'OPD Waiting',
                roomName: 'Entrance',
                gatewayId: 'GW_001',
              ),

              // MRI Room (Dining Room previously) - Amber
              _buildBlock(
                left: w * 0.15, top: h * 0.28, width: w * 0.37, height: h * 0.27,
                color: const Color(0xFFFF6D00),
                zoneName: 'MRI Room',
                roomName: 'Dining Room',
                gatewayId: 'GW_002',
              ),

              // General Ward (Living Room previously) - Electric Blue
              _buildBlock(
                left: w * 0.52, top: h * 0.28, width: w * 0.48, height: h * 0.54,
                color: const Color(0xFF2979FF),
                zoneName: 'General Ward',
                roomName: 'Living Room',
                gatewayId: 'GW_005',
              ),

              // X-Ray Room (Kitchen previously) - Lime Green
              _buildBlock(
                left: 0.0, top: h * 0.55, width: w * 0.52, height: h * 0.45,
                color: const Color(0xFF76FF03),
                zoneName: 'X-Ray Room',
                roomName: 'Kitchen',
                gatewayId: 'GW_004',
                textColor: Colors.black87,
              ),

              // Recovery Room (Balcony previously) - Coral Pink
              _buildBlock(
                left: w * 0.52, top: h * 0.82, width: w * 0.48, height: h * 0.18,
                color: const Color(0xFFFF4081),
                zoneName: 'Recovery Room',
                roomName: 'Balcony',
                gatewayId: null, // Unassigned for now
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBlock({
    required double left,
    required double top,
    required double width,
    required double height,
    required Color color,
    required String zoneName,
    required String roomName,
    String? gatewayId,
    Color textColor = Colors.white,
    bool isEmpty = false,
  }) {
    // Check if any active patient is currently in this zone
    bool hasPatients = false;
    if (gatewayId != null) {
      hasPatients = widget.activePatients.any((p) => p['gateway_id'] == gatewayId);
    } else if (zoneName.isNotEmpty && zoneName != 'Staircase') {
      hasPatients = widget.activePatients.any((p) => p['current_zone'] == zoneName);
    }

    Widget content = Container(
      margin: const EdgeInsets.all(2.0), // Wall thickness
      decoration: BoxDecoration(
        color: color.withOpacity(hasPatients ? 0.75 : 0.20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: hasPatients ? Colors.white : color.withOpacity(0.4),
          width: hasPatients ? 3.0 : 1.0,
        ),
      ),
      child: isEmpty 
          ? _buildHatchPattern(color)
          : Padding(
              padding: const EdgeInsets.all(4.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (zoneName.isNotEmpty)
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: Text(
                          zoneName,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  if (roomName.isNotEmpty)
                    Text(
                      roomName,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: textColor.withOpacity(0.7),
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (gatewayId != null)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        gatewayId,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                ],
              ),
            ),
    );

    // Apply pulsing blur if patients are present
    if (hasPatients) {
      content = AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: color,
                  blurRadius: 15 * _pulseAnimation.value,
                  spreadRadius: 2 * _pulseAnimation.value,
                )
              ],
            ),
            child: child,
          );
        },
        child: content,
      );
    }

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isEmpty || zoneName == 'Staircase'
              ? null
              : () => widget.onZoneTap(zoneName, gatewayId),
          child: content,
        ),
      ),
    );
  }

  Widget _buildHatchPattern(Color color) {
    return CustomPaint(
      painter: _HatchPainter(color: Colors.black26),
    );
  }
}

class _HatchPainter extends CustomPainter {
  final Color color;
  _HatchPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    
    // Draw an X
    canvas.drawLine(Offset(0, 0), Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
