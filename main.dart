import 'dart:html' as html;
import 'dart:math';
import 'dart:ui';
import 'package:collection/collection.dart';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/palette.dart';
import 'package:flame_forge2d/flame_forge2d.dart' hide Particle, World;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Image, Gradient;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(
    const PadracingWidget(),
  );
}

final List<Map<LogicalKeyboardKey, LogicalKeyboardKey>> playersKeys = [
  {
    LogicalKeyboardKey.arrowUp: LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown: LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft: LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight: LogicalKeyboardKey.arrowRight,
  },
  {
    LogicalKeyboardKey.keyW: LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.keyS: LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.keyA: LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.keyD: LogicalKeyboardKey.arrowRight,
  },
];

class PadRacingGame extends Forge2DGame with KeyboardEvents {
  static const String description = '''
     This is an example game that uses Forge2D to handle the physics.
     In this game you should finish 3 laps in as little time as possible, it can
     be played as single player or with two players (on the same keyboard).
     Watch out for the balls, they make your car spin.
  ''';

  PadRacingGame() : super(gravity: Vector2.zero(), zoom: 1);

  @override
  Color backgroundColor() => Colors.black;

  static Vector2 trackSize = Vector2.all(500);
  static double playZoom = 8.0;
  static const int numberOfLaps = 3;
  late final World cameraWorld;
  late CameraComponent startCamera;
  late List<Map<LogicalKeyboardKey, LogicalKeyboardKey>> activeKeyMaps;
  late List<Set<LogicalKeyboardKey>> pressedKeySets;
  final cars = <Car>[];
  bool isGameOver = true;
  Car? winner;
  double _timePassed = 0;

  @override
  Future<void> onLoad() async {
    children.register<CameraComponent>();
    cameraWorld = World();
    add(cameraWorld);

    final walls = createWalls(trackSize);
    final bigBall = Ball(position: Vector2(200, 245), isMovable: false);
    cameraWorld.addAll([
      LapLine(1, Vector2(25, 50), Vector2(50, 5), false),
      LapLine(2, Vector2(25, 70), Vector2(50, 5), false),
      LapLine(3, Vector2(52.5, 25), Vector2(5, 50), true),
      bigBall,
      ...walls,
      ...createBalls(trackSize, walls, bigBall),
    ]);

    openMenu();
  }

  void openMenu() {
    overlays.add('menu');
    final zoomLevel = min(
      canvasSize.x / trackSize.x,
      canvasSize.y / trackSize.y,
    );
    startCamera = CameraComponent(
      world: cameraWorld,
    )
      ..viewfinder.position = trackSize / 2
      ..viewfinder.anchor = Anchor.center
      ..viewfinder.zoom = zoomLevel - 0.2;
    add(startCamera);
  }

  void prepareStart({required int numberOfPlayers}) {
    startCamera.viewfinder
      ..add(
        ScaleEffect.to(
          Vector2.all(playZoom),
          EffectController(duration: 1.0),
          onComplete: () => start(numberOfPlayers: numberOfPlayers),
        ),
      )
      ..add(
        MoveEffect.to(
          Vector2.all(20),
          EffectController(duration: 1.0),
        ),
      );
  }

  void start({required int numberOfPlayers}) {
    isGameOver = false;
    overlays.remove('menu');
    startCamera.removeFromParent();
    final isHorizontal = canvasSize.x > canvasSize.y;
    Vector2 alignedVector({
      required double longMultiplier,
      double shortMultiplier = 1.0,
    }) {
      return Vector2(
        isHorizontal
            ? canvasSize.x * longMultiplier
            : canvasSize.x * shortMultiplier,
        !isHorizontal
            ? canvasSize.y * longMultiplier
            : canvasSize.y * shortMultiplier,
      );
    }

    final viewportSize = alignedVector(longMultiplier: 1 / numberOfPlayers);

    RectangleComponent viewportRimGenerator() =>
        RectangleComponent(size: viewportSize, anchor: Anchor.topLeft)
          ..paint.color = GameColors.blue.color
          ..paint.strokeWidth = 2.0
          ..paint.style = PaintingStyle.stroke;
    final cameras = List.generate(numberOfPlayers, (i) {
      return CameraComponent(
        world: cameraWorld,
      )
        ..viewfinder.anchor = Anchor.center
        ..viewfinder.zoom = playZoom;
    });

    final mapCameraSize = Vector2.all(500);
    const mapCameraZoom = 0.5;
    final mapCameras = List.generate(numberOfPlayers, (i) {
      return CameraComponent(
        world: cameraWorld,
      )
        ..viewfinder.anchor = Anchor.topLeft
        ..viewfinder.zoom = mapCameraZoom;
    });
    addAll(cameras);

    for (var i = 0; i < numberOfPlayers; i++) {
      final car = Car(playerNumber: i, cameraComponent: cameras[i]);
      final lapText = LapText(
        car: car,
        position: Vector2.all(100),
      );

      car.lapNotifier.addListener(() {
        if (car.lapNotifier.value > numberOfLaps) {
          isGameOver = true;
          winner = car;
          overlays.add('gameover');
          lapText.addAll([
            ScaleEffect.by(
              Vector2.all(1.5),
              EffectController(duration: 0.2, alternate: true, repeatCount: 3),
            ),
            RotateEffect.by(pi * 2, EffectController(duration: 0.5)),
          ]);
        } else {
          lapText.add(
            ScaleEffect.by(
              Vector2.all(1.5),
              EffectController(duration: 0.2, alternate: true),
            ),
          );
        }
      });
      cars.add(car);
      cameraWorld.add(car);
      cameras[i].viewport.addAll([lapText, mapCameras[i]]);
    }

    pressedKeySets = List.generate(numberOfPlayers, (_) => {});
    activeKeyMaps = List.generate(numberOfPlayers, (i) => playersKeys[i]);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isGameOver) {
      return;
    }
    _timePassed += dt;
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    super.onKeyEvent(event, keysPressed);
    if (!isLoaded || isGameOver) {
      return KeyEventResult.ignored;
    }

    _clearPressedKeys();
    for (final key in keysPressed) {
      activeKeyMaps.forEachIndexed((i, keyMap) {
        if (keyMap.containsKey(key)) {
          pressedKeySets[i].add(keyMap[key]!);
        }
      });
    }
    return KeyEventResult.handled;
  }

  void _clearPressedKeys() {
    for (final pressedKeySet in pressedKeySets) {
      pressedKeySet.clear();
    }
  }

  void reset() {
    _clearPressedKeys();
    for (final keyMap in activeKeyMaps) {
      keyMap.clear();
    }
    _timePassed = 0;
    overlays.remove('gameover');
    openMenu();
    for (final car in cars) {
      car.removeFromParent();
    }
    for (final camera in children.query<CameraComponent>()) {
      camera.removeFromParent();
    }
  }

  String _maybePrefixZero(int number) {
    if (number < 10) {
      return '0$number';
    }
    return number.toString();
  }

  String get timePassed {
    final minutes = _maybePrefixZero((_timePassed / 60).floor());
    final seconds = _maybePrefixZero((_timePassed % 60).floor());
    final ms = _maybePrefixZero(((_timePassed % 1) * 100).floor());
    return [minutes, seconds, ms].join(':');
  }
}

class Ball extends BodyComponent<PadRacingGame> with ContactCallbacks {
  final double radius;
  final Vector2 position;
  final double rotation;
  final bool isMovable;
  final rng = Random();
  late final Paint _shaderPaint;

  Ball({
    required this.position,
    this.radius = 80.0,
    this.rotation = 1.0,
    this.isMovable = true,
  }) : super(priority: 3);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    renderBody = false;
    _shaderPaint = GameColors.green.paint
      ..shader = Gradient.radial(
        Offset.zero,
        radius,
        [
          GameColors.green.color,
          BasicPalette.black.color,
        ],
        null,
        TileMode.clamp,
        null,
        Offset(radius / 2, radius / 2),
      );
  }

  @override
  Body createBody() {
    final def = BodyDef()
      ..userData = this
      ..type = isMovable ? BodyType.dynamic : BodyType.kinematic
      ..position = position;
    final body = world.createBody(def)..angularVelocity = rotation;

    final shape = CircleShape()..radius = radius;
    final fixtureDef = FixtureDef(shape)
      ..restitution = 0.5
      ..friction = 0.5;
    return body..createFixture(fixtureDef);
  }

  @override
  void render(Canvas canvas) {
    canvas.drawCircle(Offset.zero, radius, _shaderPaint);
  }

  @override
  void beginContact(Object other, Contact contact) {
    if (isMovable && other is Car) {
      final carBody = other.body;
      carBody.applyAngularImpulse(3 * carBody.mass * 100);
    }
  }

  late Rect asRect = Rect.fromCircle(
    center: position.toOffset(),
    radius: radius,
  );
}

List<Ball> createBalls(Vector2 trackSize, List<Wall> walls, Ball bigBall) {
  final balls = <Ball>[];
  final rng = Random();
  while (balls.length < 20) {
    final ball = Ball(
      position: Vector2.random(rng)..multiply(trackSize),
      radius: 3.0 + rng.nextInt(5),
      rotation: (rng.nextBool() ? 1 : -1) * rng.nextInt(5).toDouble(),
    );
    final touchesBall = ball.position.distanceTo(bigBall.position) <
        ball.radius + bigBall.radius;
    if (!touchesBall) {
      final touchesWall =
          walls.any((wall) => wall.asRect.overlaps(ball.asRect));
      if (!touchesWall) {
        balls.add(ball);
      }
    }
  }
  return balls;
}

class Car extends BodyComponent<PadRacingGame> with HasGameRef<PadRacingGame> {
  Car({required this.playerNumber, required this.cameraComponent})
      : super(
          priority: 3,
          paint: Paint()..color = colors[playerNumber],
        );

  static final colors = [
    GameColors.green.color,
    GameColors.blue.color,
  ];

  late final List<Tire> tires;
  final ValueNotifier<int> lapNotifier = ValueNotifier<int>(1);
  final int playerNumber;
  final Set<LapLine> passedStartControl = {};
  final CameraComponent cameraComponent;
  late final Image _image;
  final size = const Size(6, 10);
  final scale = 10.0;
  late final _renderPosition = -size.toOffset() / 2;
  late final _scaledRect = (size * scale).toRect();
  late final _renderRect = _renderPosition & size;

  final vertices = <Vector2>[
    Vector2(1.5, -5.0),
    Vector2(3.0, -2.5),
    Vector2(2.8, 0.5),
    Vector2(1.0, 5.0),
    Vector2(-1.0, 5.0),
    Vector2(-2.8, 0.5),
    Vector2(-3.0, -2.5),
    Vector2(-1.5, -5.0),
  ];

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder, _scaledRect);
    final path = Path();
    final bodyPaint = Paint()..color = paint.color;
    for (var i = 0.0; i < _scaledRect.width / 4; i++) {
      bodyPaint.color = bodyPaint.color.darken(0.1);
      path.reset();
      final offsetVertices = vertices
          .map(
            (v) =>
                v.toOffset() * scale -
                Offset(i * v.x.sign, i * v.y.sign) +
                _scaledRect.bottomRight / 2,
          )
          .toList();
      path.addPolygon(offsetVertices, true);
      canvas.drawPath(path, bodyPaint);
    }
    final picture = recorder.endRecording();
    _image = await picture.toImage(
      _scaledRect.width.toInt(),
      _scaledRect.height.toInt(),
    );
  }

  @override
  Body createBody() {
    final startPosition =
        Vector2(20, 30) + Vector2(15, 0) * playerNumber.toDouble();
    final def = BodyDef()
      ..type = BodyType.dynamic
      ..position = startPosition;
    final body = world.createBody(def)
      ..userData = this
      ..angularDamping = 3.0;

    final shape = PolygonShape()..set(vertices);
    final fixtureDef = FixtureDef(shape)
      ..density = 0.2
      ..restitution = 2.0;
    body.createFixture(fixtureDef);

    final jointDef = RevoluteJointDef()
      ..bodyA = body
      ..enableLimit = true
      ..lowerAngle = 0.0
      ..upperAngle = 0.0
      ..localAnchorB.setZero();

    tires = List.generate(4, (i) {
      final isFrontTire = i <= 1;
      final isLeftTire = i.isEven;
      return Tire(
        car: this,
        pressedKeys: gameRef.pressedKeySets[playerNumber],
        isFrontTire: isFrontTire,
        isLeftTire: isLeftTire,
        jointDef: jointDef,
        isTurnableTire: isFrontTire,
      );
    });

    gameRef.cameraWorld.addAll(tires);
    return body;
  }

  @override
  void update(double dt) {
    cameraComponent.viewfinder.position = body.position;
  }

  @override
  void render(Canvas canvas) {
    canvas.drawImageRect(
      _image,
      _scaledRect,
      _renderRect,
      paint,
    );
  }

  @override
  void onRemove() {
    for (final tire in tires) {
      tire.removeFromParent();
    }
  }
}

enum GameColors {
  green,
  blue,
}

extension GameColorExtension on GameColors {
  Color get color {
    switch (this) {
      case GameColors.green:
        return ColorExtension.fromRGBHexString('#14F596');
      case GameColors.blue:
        return ColorExtension.fromRGBHexString('#81DDF9');
    }
  }

  Paint get paint => Paint()..color = color;
}

class GameOver extends StatelessWidget {
  const GameOver(this.game, {super.key});

  final PadRacingGame game;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Wrap(
          children: [
            MenuCard(
              children: [
                Text(
                  'Player ${game.winner!.playerNumber + 1} wins!',
                  style: textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  'Time: ${game.timePassed}',
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: game.reset,
                  child: const Text('Restart'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LapLine extends BodyComponent with ContactCallbacks {
  LapLine(this.id, this.position, this.size, this.isFinish)
      : super(priority: 1);

  final int id;
  final bool isFinish;
  final Vector2 position;
  final Vector2 size;
  late final Rect rect = size.toRect();
  Image? _finishOverlay;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    if (isFinish) {
      _finishOverlay = await createFinishOverlay();
    }
  }

  @override
  Body createBody() {
    paint.color = (isFinish ? GameColors.green.color : GameColors.green.color)
      ..withOpacity(0.5);
    paint
      ..style = PaintingStyle.fill
      ..shader = Gradient.radial(
        (size / 2).toOffset(),
        max(size.x, size.y),
        [
          paint.color,
          Colors.black,
        ],
      );

    final groundBody = world.createBody(
      BodyDef(
        position: position,
        userData: this,
      ),
    );
    final shape = PolygonShape()..setAsBoxXY(size.x / 2, size.y / 2);
    final fixtureDef = FixtureDef(shape, isSensor: true);
    return groundBody..createFixture(fixtureDef);
  }

  late final Rect _scaledRect = (size * 10).toRect();
  late final Rect _drawRect = size.toRect();

  Future<Image> createFinishOverlay() async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder, _scaledRect);
    final step = _scaledRect.width / 2;
    final black = BasicPalette.black.paint();

    for (var i = 0; i * step < _scaledRect.height; i++) {
      canvas.drawRect(
        Rect.fromLTWH(i.isEven ? 0 : step, i * step, step, step),
        black,
      );
    }
    final picture = recorder.endRecording();
    return picture.toImage(
      _scaledRect.width.toInt(),
      _scaledRect.height.toInt(),
    );
  }

  @override
  void render(Canvas canvas) {
    canvas.translate(-size.x / 2, -size.y / 2);
    canvas.drawRect(rect, paint);
    if (_finishOverlay != null) {
      canvas.drawImageRect(_finishOverlay!, _scaledRect, _drawRect, paint);
    }
  }

  @override
  void beginContact(Object other, Contact contact) {
    if (other is! Car) {
      return;
    }
    if (isFinish && other.passedStartControl.length == 2) {
      other.lapNotifier.value++;
      other.passedStartControl.clear();
    } else if (!isFinish) {
      other.passedStartControl
          .removeWhere((passedControl) => passedControl.id > id);
      other.passedStartControl.add(this);
    }
  }
}

class LapText extends PositionComponent with HasGameRef<PadRacingGame> {
  LapText({required this.car, required Vector2 position})
      : super(position: position);

  final Car car;
  late final ValueNotifier<int> lapNotifier = car.lapNotifier;
  late final TextComponent _timePassedComponent;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final textStyle = GoogleFonts.vt323(
      fontSize: 35,
      color: car.paint.color,
    );
    final defaultRenderer = TextPaint(style: textStyle);
    final lapCountRenderer = TextPaint(
      style: textStyle.copyWith(fontSize: 55, fontWeight: FontWeight.bold),
    );
    add(
      TextComponent(
        text: 'Lap',
        position: Vector2(0, -20),
        anchor: Anchor.center,
        textRenderer: defaultRenderer,
      ),
    );
    final lapCounter = TextComponent(
      position: Vector2(0, 10),
      anchor: Anchor.center,
      textRenderer: lapCountRenderer,
    );
    add(lapCounter);
    void updateLapText() {
      if (lapNotifier.value <= PadRacingGame.numberOfLaps) {
        final prefix = lapNotifier.value < 10 ? '0' : '';
        lapCounter.text = '$prefix${lapNotifier.value}';
      } else {
        lapCounter.text = 'DONE';
      }
    }

    _timePassedComponent = TextComponent(
      position: Vector2(0, 70),
      anchor: Anchor.center,
      textRenderer: defaultRenderer,
    );
    add(_timePassedComponent);

    _backgroundPaint = Paint()
      ..color = car.paint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    lapNotifier.addListener(updateLapText);
    updateLapText();
  }

  @override
  void update(double dt) {
    if (gameRef.isGameOver) {
      return;
    }
    _timePassedComponent.text = gameRef.timePassed;
  }

  final _backgroundRect = RRect.fromRectAndRadius(
    Rect.fromCircle(center: Offset.zero, radius: 50),
    const Radius.circular(10),
  );
  late final Paint _backgroundPaint;

  @override
  void render(Canvas canvas) {
    canvas.drawRRect(_backgroundRect, _backgroundPaint);
  }
}

class Menu extends StatelessWidget {
  const Menu(this.game, {super.key});

  final PadRacingGame game;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Wrap(
          children: [
            Column(
              children: [
                MenuCard(
                  children: [
                    Text(
                      'PadRacing',
                      style: textTheme.headlineMedium,
                    ),
                    Text(
                      'First to 3 laps win',
                      style: textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      child: const Text('1 Player'),
                      onPressed: () {
                        game.prepareStart(numberOfPlayers: 1);
                      },
                    ),
                    Text(
                      'Arrow keys',
                      style: textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      child: const Text('2 Players'),
                      onPressed: () {
                        game.prepareStart(numberOfPlayers: 2);
                      },
                    ),
                    Text(
                      'ASDW',
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
                MenuCard(
                  children: [
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'Made by ',
                            style: textTheme.bodyMedium,
                          ),
                          TextSpan(
                            text: 'Lukas Klingsbo',
                            style: textTheme.bodyMedium
                                ?.copyWith(color: GameColors.green.color),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                //ignore: unsafe_html
                                html.window.open(
                                  'https://github.com/spydon',
                                  '_blank',
                                );
                              },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'Checkout the ',
                            style: textTheme.bodyMedium,
                          ),
                          TextSpan(
                            text: 'repository',
                            style: textTheme.bodyMedium
                                ?.copyWith(color: GameColors.green.color),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                //ignore: unsafe_html
                                html.window.open(
                                  'https://github.com/flame-engine/flame/tree/main/examples/games/padracing',
                                  '_blank',
                                );
                              },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MenuCard extends StatelessWidget {
  const MenuCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black,
      shadowColor: GameColors.green.color,
      elevation: 10,
      margin: const EdgeInsets.only(bottom: 20),
      child: Container(
        margin: const EdgeInsets.all(20),
        child: Column(
          children: children,
        ),
      ),
    );
  }
}

class PadracingWidget extends StatelessWidget {
  const PadracingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      textTheme: TextTheme(
        headlineSmall: GoogleFonts.vt323(
          fontSize: 35,
          color: Colors.white,
        ),
        titleSmall: GoogleFonts.vt323(
          fontSize: 30,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: GoogleFonts.vt323(
          fontSize: 28,
          color: Colors.grey,
        ),
        bodySmall: GoogleFonts.vt323(
          fontSize: 18,
          color: Colors.grey,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(150, 50),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        hoverColor: Colors.red.shade700,
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
        ),
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
        ),
        errorBorder: UnderlineInputBorder(
          borderSide: BorderSide(
            color: Colors.red.shade700,
          ),
        ),
      ),
    );

    return MaterialApp(
      title: 'PadRacing',
      home: GameWidget<PadRacingGame>(
        game: PadRacingGame(),
        loadingBuilder: (context) => Center(
          child: Text(
            'Loading...',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        overlayBuilderMap: {
          'menu': (_, game) => Menu(game),
          'gameover': (_, game) => GameOver(game),
        },
        initialActiveOverlays: const ['menu'],
      ),
      theme: theme,
    );
  }
}

class Tire extends BodyComponent<PadRacingGame> with HasGameRef<PadRacingGame> {
  Tire({
    required this.car,
    required this.pressedKeys,
    required this.isFrontTire,
    required this.isLeftTire,
    required this.jointDef,
    this.isTurnableTire = false,
  }) : super(
          paint: Paint()
            ..color = car.paint.color
            ..strokeWidth = 0.2
            ..style = PaintingStyle.stroke,
          priority: 2,
        );

  static const double _backTireMaxDriveForce = 300.0;
  static const double _frontTireMaxDriveForce = 600.0;
  static const double _backTireMaxLateralImpulse = 8.5;
  static const double _frontTireMaxLateralImpulse = 7.5;

  final Car car;
  final size = Vector2(0.5, 1.25);
  late final RRect _renderRect = RRect.fromLTRBR(
    -size.x,
    -size.y,
    size.x,
    size.y,
    const Radius.circular(0.3),
  );

  final Set<LogicalKeyboardKey> pressedKeys;

  late final double _maxDriveForce =
      isFrontTire ? _frontTireMaxDriveForce : _backTireMaxDriveForce;
  late final double _maxLateralImpulse =
      isFrontTire ? _frontTireMaxLateralImpulse : _backTireMaxLateralImpulse;

  // Make mutable if ice or something should be implemented
  final double _currentTraction = 1.0;

  final double _maxForwardSpeed = 250.0;
  final double _maxBackwardSpeed = -40.0;

  final RevoluteJointDef jointDef;
  late final RevoluteJoint joint;
  final bool isTurnableTire;
  final bool isFrontTire;
  final bool isLeftTire;

  final double _lockAngle = 0.6;
  final double _turnSpeedPerSecond = 4;

  final Paint _black = BasicPalette.black.paint();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    gameRef.cameraWorld.add(Trail(car: car, tire: this));
  }

  @override
  Body createBody() {
    final jointAnchor = isFrontTire
        ? Vector2(isLeftTire ? -3.0 : 3.0, 3.5)
        : Vector2(isLeftTire ? -3.0 : 3.0, -4.25);

    final def = BodyDef()
      ..type = BodyType.dynamic
      ..position = car.body.position + jointAnchor;
    final body = world.createBody(def)..userData = this;

    final polygonShape = PolygonShape()..setAsBoxXY(0.5, 1.25);
    body.createFixtureFromShape(polygonShape).userData = this;

    jointDef.bodyB = body;
    jointDef.localAnchorA.setFrom(jointAnchor);
    world.createJoint(joint = RevoluteJoint(jointDef));
    joint.setLimits(0, 0);
    return body;
  }

  @override
  void update(double dt) {
    if (body.isAwake || pressedKeys.isNotEmpty) {
      _updateTurn(dt);
      _updateFriction();
      if (!gameRef.isGameOver) {
        _updateDrive();
      }
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRRect(_renderRect, _black);
    canvas.drawRRect(_renderRect, paint);
  }

  void _updateFriction() {
    final impulse = _lateralVelocity
      ..scale(-body.mass)
      ..clampScalar(-_maxLateralImpulse, _maxLateralImpulse)
      ..scale(_currentTraction);
    body.applyLinearImpulse(impulse);
    body.applyAngularImpulse(
      0.1 * _currentTraction * body.getInertia() * -body.angularVelocity,
    );

    final currentForwardNormal = _forwardVelocity;
    final currentForwardSpeed = currentForwardNormal.length;
    currentForwardNormal.normalize();
    final dragForceMagnitude = -2 * currentForwardSpeed;
    body.applyForce(
      currentForwardNormal..scale(_currentTraction * dragForceMagnitude),
    );
  }

  void _updateDrive() {
    var desiredSpeed = 0.0;
    if (pressedKeys.contains(LogicalKeyboardKey.arrowUp)) {
      desiredSpeed = _maxForwardSpeed;
    }
    if (pressedKeys.contains(LogicalKeyboardKey.arrowDown)) {
      desiredSpeed += _maxBackwardSpeed;
    }

    final currentForwardNormal = body.worldVector(Vector2(0.0, 1.0));
    final currentSpeed = _forwardVelocity.dot(currentForwardNormal);
    var force = 0.0;
    if (desiredSpeed < currentSpeed) {
      force = -_maxDriveForce;
    } else if (desiredSpeed > currentSpeed) {
      force = _maxDriveForce;
    }

    if (force.abs() > 0) {
      body.applyForce(currentForwardNormal..scale(_currentTraction * force));
    }
  }

  void _updateTurn(double dt) {
    var desiredAngle = 0.0;
    var desiredTorque = 0.0;
    var isTurning = false;
    if (pressedKeys.contains(LogicalKeyboardKey.arrowLeft)) {
      desiredTorque = -15.0;
      desiredAngle = -_lockAngle;
      isTurning = true;
    }
    if (pressedKeys.contains(LogicalKeyboardKey.arrowRight)) {
      desiredTorque += 15.0;
      desiredAngle += _lockAngle;
      isTurning = true;
    }
    if (isTurnableTire && isTurning) {
      final turnPerTimeStep = _turnSpeedPerSecond * dt;
      final angleNow = joint.jointAngle();
      final angleToTurn =
          (desiredAngle - angleNow).clamp(-turnPerTimeStep, turnPerTimeStep);
      final angle = angleNow + angleToTurn;
      joint.setLimits(angle, angle);
    } else {
      joint.setLimits(0, 0);
    }
    body.applyTorque(desiredTorque);
  }

  // Cached Vectors to reduce unnecessary object creation.
  final Vector2 _worldLeft = Vector2(1.0, 0.0);
  final Vector2 _worldUp = Vector2(0.0, -1.0);

  Vector2 get _lateralVelocity {
    final currentRightNormal = body.worldVector(_worldLeft);
    return currentRightNormal
      ..scale(currentRightNormal.dot(body.linearVelocity));
  }

  Vector2 get _forwardVelocity {
    final currentForwardNormal = body.worldVector(_worldUp);
    return currentForwardNormal
      ..scale(currentForwardNormal.dot(body.linearVelocity));
  }
}

class Trail extends Component with HasPaint {
  Trail({
    required this.car,
    required this.tire,
  }) : super(priority: 1);

  final Car car;
  final Tire tire;

  final trail = <Offset>[];
  final _trailLength = 30;

  @override
  Future<void> onLoad() async {
    paint
      ..color = (tire.paint.color.withOpacity(0.9))
      ..strokeWidth = 1.0;
  }

  @override
  void update(double dt) {
    if (tire.body.linearVelocity.length2 > 100) {
      if (trail.length > _trailLength) {
        trail.removeAt(0);
      }
      final trailPoint = tire.body.position.toOffset();
      trail.add(trailPoint);
    } else if (trail.isNotEmpty) {
      trail.removeAt(0);
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawPoints(PointMode.polygon, trail, paint);
  }
}

List<Wall> createWalls(Vector2 size) {
  final topCenter = Vector2(size.x / 2, 0);
  final bottomCenter = Vector2(size.x / 2, size.y);
  final leftCenter = Vector2(0, size.y / 2);
  final rightCenter = Vector2(size.x, size.y / 2);

  final filledSize = size.clone() + Vector2.all(5);
  return [
    Wall(topCenter, Vector2(filledSize.x, 5)),
    Wall(leftCenter, Vector2(5, filledSize.y)),
    Wall(Vector2(52.5, 240), Vector2(5, 380)),
    Wall(Vector2(200, 50), Vector2(300, 5)),
    Wall(Vector2(72.5, 300), Vector2(5, 400)),
    Wall(Vector2(180, 100), Vector2(220, 5)),
    Wall(Vector2(350, 105), Vector2(5, 115)),
    Wall(Vector2(310, 160), Vector2(240, 5)),
    Wall(Vector2(211.5, 400), Vector2(283, 5)),
    Wall(Vector2(351, 312.5), Vector2(5, 180)),
    Wall(Vector2(430, 302.5), Vector2(5, 290)),
    Wall(Vector2(292.5, 450), Vector2(280, 5)),
    Wall(bottomCenter, Vector2(filledSize.y, 5)),
    Wall(rightCenter, Vector2(5, filledSize.y)),
  ];
}

class Wall extends BodyComponent<PadRacingGame> {
  Wall(this.position, this.size) : super(priority: 3);

  final Vector2 position;
  final Vector2 size;

  final Random rng = Random();
  late final Image _image;

  final scale = 10.0;
  late final _renderPosition = -size.toOffset() / 2;
  late final _scaledRect = (size * scale).toRect();
  late final _renderRect = _renderPosition & size.toSize();

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    paint.color = ColorExtension.fromRGBHexString('#14F596');

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder, _scaledRect);
    final drawSize = _scaledRect.size.toVector2();
    final center = (drawSize / 2).toOffset();
    const step = 1.0;

    canvas.drawRect(
      Rect.fromCenter(center: center, width: drawSize.x, height: drawSize.y),
      BasicPalette.black.paint(),
    );
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = step;
    for (var x = 0; x < 30; x++) {
      canvas.drawRect(
        Rect.fromCenter(center: center, width: drawSize.x, height: drawSize.y),
        paint,
      );
      paint.color = paint.color.darken(0.07);
      drawSize.x -= step;
      drawSize.y -= step;
    }
    final picture = recorder.endRecording();
    _image = await picture.toImage(
      _scaledRect.width.toInt(),
      _scaledRect.height.toInt(),
    );
  }

  @override
  void render(Canvas canvas) {
    canvas.drawImageRect(
      _image,
      _scaledRect,
      _renderRect,
      paint,
    );
  }

  @override
  Body createBody() {
    final def = BodyDef()
      ..type = BodyType.static
      ..position = position;
    final body = world.createBody(def)
      ..userData = this
      ..angularDamping = 3.0;

    final shape = PolygonShape()..setAsBoxXY(size.x / 2, size.y / 2);
    final fixtureDef = FixtureDef(shape)..restitution = 0.5;
    return body..createFixture(fixtureDef);
  }

  late Rect asRect = Rect.fromCenter(
    center: position.toOffset(),
    width: size.x,
    height: size.y,
  );
}
