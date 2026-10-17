import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/main.dart' show reportBootstrapFailure;
import 'package:stack_trace/stack_trace.dart' as async_stack;

void main() {
  late FlutterExceptionHandler? previousHandler;
  late List<FlutterErrorDetails> reported;

  setUp(() {
    previousHandler = FlutterError.onError;
    reported = [];
    FlutterError.onError = reported.add;
  });
  tearDown(() => FlutterError.onError = previousHandler);

  test('startup error and stack survive a secondary cleanup failure', () async {
    final startupError = StateError('Initialization failed');
    final cleanupError = StateError('Database close failed');
    final startupStack = StackTrace.current;
    final cleanupStack = StackTrace.fromString('database cleanup stack');
    var closes = 0;
    await reportBootstrapFailure(startupError, startupStack,
        closeDatabase: () async {
      closes++;
      Error.throwWithStackTrace(cleanupError, cleanupStack);
    });
    expect(closes, 1);
    expect(reported.map((details) => details.exception),
        [same(startupError), same(cleanupError)]);
    expect(reported.first.stack, same(startupStack));
    expect(reported.last.stack.toString(), cleanupStack.toString());
    expect(reported.first.library, 'RainLink bootstrap');
    expect(reported.last.library, 'RainLink bootstrap cleanup');
  });

  test('failure before database acquisition needs no cleanup', () async {
    final error = StateError('Database not opened');
    await reportBootstrapFailure(error, StackTrace.current);
    expect(reported, hasLength(1));
    expect(reported.single.exception, same(error));
  });

  test('asynchronous database chains render without hiding the startup error',
      () async {
    final chain = async_stack.Chain([
      async_stack.Trace.parseVM(
          '#0      openDatabase (file:///database.dart:7:1)'),
      async_stack.Trace.parseVM('#0      startApp (file:///main.dart:3:1)'),
    ]);
    var closed = false;
    final error = StateError('Database initialization failed');
    await reportBootstrapFailure(error, chain, closeDatabase: () async {
      closed = true;
    });
    expect(closed, isTrue);
    expect(reported.single.exception, same(error));
    final stack = reported.single.stack.toString();
    expect(() => StackFrame.fromStackString(stack), returnsNormally);
    expect(stack, contains('openDatabase'));
    expect(stack, contains('startApp'));
    expect(stack, isNot(contains('===== asynchronous gap')));
  });

  test('a package trace from cleanup also remains renderable', () async {
    final error = StateError('Database close failed');
    final trace = async_stack.Trace.current();
    await reportBootstrapFailure(
        StateError('Startup failed'), StackTrace.current,
        closeDatabase: () async => Error.throwWithStackTrace(error, trace));
    expect(reported.last.exception, same(error));
    expect(() => StackFrame.fromStackString(reported.last.stack.toString()),
        returnsNormally);
  });
}
