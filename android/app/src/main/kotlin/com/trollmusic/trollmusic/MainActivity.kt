package com.trollmusic.trollmusic

import com.ryanheise.audioservice.AudioServiceActivity

// audio_service на Android должен делить FlutterEngine с активностью.
// Обычный FlutterActivity приводит к тому, что AudioService.init() не
// завершается, runApp() не вызывается и приложение висит на чёрном экране.
class MainActivity : AudioServiceActivity()
