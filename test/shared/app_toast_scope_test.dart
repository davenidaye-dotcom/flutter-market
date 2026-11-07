import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/shared/widgets/page_app_bar.dart';

void main() {
  testWidgets('hidden later layer does not take the toast', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            Expanded(
              child: AppToastScope(
                active: true,
                child: SizedBox(key: Key('ca')),
              ),
            ),
            Expanded(
              child: AppToastScope(
                active: false,
                child: SizedBox(key: Key('ft')),
              ),
            ),
          ],
        ),
      ),
    );

    AppToast.success('bet-ok');
    await tester.pump();

    expect(find.text('bet-ok'), findsOneWidget);
  });

  testWidgets('toast follows the layer that becomes visible', (tester) async {
    late void Function(bool canada) show;
    await tester.pumpWidget(
      MaterialApp(
        home: _ToggleHost(
          onReady: (update) => show = update,
        ),
      ),
    );

    show(false);
    await tester.pump();
    AppToast.success('boat');
    await tester.pump();
    expect(find.text('boat'), findsOneWidget);

    show(true);
    await tester.pump();
    AppToast.success('bet-ok');
    await tester.pump();
    expect(find.text('bet-ok'), findsOneWidget);
  });
}

class _ToggleHost extends StatefulWidget {
  const _ToggleHost({required this.onReady});

  final void Function(void Function(bool canada)) onReady;

  @override
  State<_ToggleHost> createState() => _ToggleHostState();
}

class _ToggleHostState extends State<_ToggleHost> {
  var _canada = true;

  @override
  void initState() {
    super.initState();
    widget.onReady((canada) => setState(() => _canada = canada));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: AppToastScope(
            active: _canada,
            child: const SizedBox(key: Key('ca')),
          ),
        ),
        Expanded(
          child: AppToastScope(
            active: !_canada,
            child: const SizedBox(key: Key('ft')),
          ),
        ),
      ],
    );
  }
}
