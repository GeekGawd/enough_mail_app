import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:enough_platform_widgets/enough_platform_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../l10n/app_localizations.g.dart';
import 'app_lifecycle/provider.dart';
import 'l10n/extension.dart';
import 'locator.dart';
import 'logger.dart';
import 'routes.dart';
import 'screens/all_screens.dart';
import 'services/app_service.dart';
import 'services/background_service.dart';
import 'services/biometrics_service.dart';
import 'services/i18n_service.dart';
import 'services/key_service.dart';
import 'services/mail_service.dart';
import 'services/navigation_service.dart';
import 'services/notification_service.dart';
import 'services/scaffold_messenger_service.dart';
import 'settings/provider.dart';
import 'settings/theme/provider.dart';
import 'widgets/inherited_widgets.dart';
// AppStyles appStyles = AppStyles.instance;

void main() {
  setupLocator();
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  late Future<MailService> _appInitialization;
  Locale? _locale;
  bool _isInitialized = false;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    _appInitialization = _initApp();
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isInitialized) {
      final settings = ref.read(settingsProvider);
      locator<AppService>().didChangeAppLifecycleState(state, settings);
      ref.read(appLifecycleStateProvider.notifier).state = state;
    }
  }

  Future<MailService> _initApp() async {
    await ref.read(settingsProvider.notifier).init();
    if (context.mounted) {
      ref.read(themeProvider.notifier).init(context);
    }
    final settings = ref.read(settingsProvider);
    final i18nService = locator<I18nService>();
    final languageTag = settings.languageTag;
    if (languageTag != null) {
      final settingsLocale = AppLocalizations.supportedLocales
          .firstWhereOrNull((l) => l.toLanguageTag() == languageTag);
      if (settingsLocale != null) {
        final settingsLocalizations =
            await AppLocalizations.delegate.load(settingsLocale);
        i18nService.init(settingsLocalizations, settingsLocale);
        setState(() {
          _locale = settingsLocale;
        });
      }
    }
    final mailService = locator<MailService>();
    // key service is required before mail service due to Oauth configs
    await locator<KeyService>().init();
    await mailService.init(i18nService.localizations, settings);

    if (mailService.messageSource != null) {
      final state = MailServiceWidget.of(context);
      if (state != null) {
        state
          ..account = mailService.currentAccount
          ..accounts = mailService.accounts;
      }
      // on ios show the app drawer:
      if (Platform.isIOS) {
        await locator<NavigationService>()
            .push(Routes.appDrawer, replace: true);
      }

      /// the app has at least one configured account
      unawaited(locator<NavigationService>().push(
        Routes.messageSource,
        arguments: mailService.messageSource,
        fade: true,
        replace: !Platform.isIOS,
      ));
      // check for a tapped notification that started the app:
      final notificationInitResult =
          await locator<NotificationService>().init();
      if (notificationInitResult !=
          NotificationServiceInitResult.appLaunchedByNotification) {
        // the app has not been launched by a notification
        await locator<AppService>().checkForShare();
      }
      if (settings.enableBiometricLock) {
        unawaited(locator<NavigationService>().push(Routes.lockScreen));
        final didAuthenticate =
            await locator<BiometricsService>().authenticate();
        if (didAuthenticate) {
          locator<NavigationService>().pop();
        }
      }
    } else {
      // this app has no mail accounts yet, so switch to welcome screen:
      unawaited(locator<NavigationService>()
          .push(Routes.welcome, fade: true, replace: true));
    }
    if (BackgroundService.isSupported) {
      await locator<BackgroundService>().init();
    }
    logger.d('App initialized');
    _isInitialized = true;

    return mailService;
  }

  @override
  Widget build(BuildContext context) {
    final themeSettingsData = ref.watch(themeProvider);

    return PlatformSnackApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: _locale,
      debugShowCheckedModeBanner: false,
      title: 'Maily',
      onGenerateRoute: AppRouter.generateRoute,
      initialRoute: Routes.splash,
      navigatorKey: locator<NavigationService>().navigatorKey,
      scaffoldMessengerKey:
          locator<ScaffoldMessengerService>().scaffoldMessengerKey,
      builder: (context, child) {
        locator<I18nService>().init(
          context.text,
          Localizations.localeOf(context),
        );
        child ??= FutureBuilder<MailService>(
          future: _appInitialization,
          builder: (context, snapshot) {
            switch (snapshot.connectionState) {
              case ConnectionState.none:
              case ConnectionState.waiting:
              case ConnectionState.active:
                return const SplashScreen();
              case ConnectionState.done:
                // in the meantime the app has navigated away
                break;
            }

            return const SizedBox.shrink();
          },
        );

        final mailService = locator<MailService>();

        return MailServiceWidget(
          account: mailService.currentAccount,
          accounts: mailService.accounts,
          messageSource: mailService.messageSource,
          child: child,
        );
      },
      // home: Builder(
      //   builder: (context) {
      //     locator<I18nService>().init(
      //         context.text!, Localizations.localeOf(context));
      //     return FutureBuilder<MailService>(
      //       future: _appInitialization,
      //       builder: (context, snapshot) {
      //         switch (snapshot.connectionState) {
      //           case ConnectionState.none:
      //           case ConnectionState.waiting:
      //           case ConnectionState.active:
      //             return SplashScreen();
      //           case ConnectionState.done:
      //             // in the meantime the app has navigated away
      //             break;
      //         }
      //         return Container();
      //       },
      //     );
      //   },
      // ),
      materialTheme: themeSettingsData.lightTheme,
      materialDarkTheme: themeSettingsData.darkTheme,
      materialThemeMode: themeSettingsData.themeMode,
      cupertinoTheme: CupertinoThemeData(
        brightness: themeSettingsData.brightness,
        //TODO support theming on Cupertino
      ),
    );
  }
}
