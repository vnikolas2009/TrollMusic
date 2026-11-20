abstract final class AppConfig {
  static const appName = 'YSPlayer';
  static const defaultWorkerUrl = 'https://ysplayer-proxy.workers.dev';
  static const mirrorTimeout = Duration(seconds: 3);
  static const requestTimeout = Duration(seconds: 15);

  static const defaultPipedInstances = <String>[
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.adminforge.de',
    'https://api.piped.private.coffee',
    'https://pipedapi.leptons.xyz',
    'https://pipedapi.drgns.space',
  ];

  static const defaultInvidiousInstances = <String>[
    'https://inv.nadeko.net',
    'https://invidious.nerdvpn.de',
    'https://yewtu.be',
    'https://invidious.f5.si',
    'https://vid.puffyan.us',
  ];

  static const audioBitrates = <int>[128, 192, 256, 320];
  static const defaultBitrate = 192;
}
