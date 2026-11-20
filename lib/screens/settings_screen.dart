import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsService = context.watch<SettingsService>();
    final settings = settingsService.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('阅读设置', style: TextStyle(fontSize: 14, color: Colors.grey)),
          ),

          // 字号
          ListTile(
            title: const Text('正文字号'),
            subtitle: Text('${settings.fontSize.toInt()}'),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: settings.fontSize,
                min: 12,
                max: 32,
                divisions: 20,
                onChanged: (v) => settingsService.update(settings.copyWith(fontSize: v)),
              ),
            ),
          ),

          // 行距
          ListTile(
            title: const Text('行间距'),
            subtitle: Text(settings.lineHeight.toStringAsFixed(1)),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: settings.lineHeight,
                min: 1.2,
                max: 2.5,
                divisions: 13,
                onChanged: (v) => settingsService.update(settings.copyWith(lineHeight: v)),
              ),
            ),
          ),

          // 首行缩进
          ListTile(
            title: const Text('首行缩进'),
            subtitle: Text('${settings.indent} 字符'),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: settings.indent.toDouble(),
                min: 0,
                max: 4,
                divisions: 4,
                onChanged: (v) => settingsService.update(settings.copyWith(indent: v.toInt())),
              ),
            ),
          ),

          const Divider(),

          // 主题
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('背景主题', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: ReaderTheme.values.map((t) {
                    final selected = t == settings.theme;
                    return GestureDetector(
                      onTap: () => settingsService.update(settings.copyWith(
                        theme: t,
                        isDarkMode: t.index >= 5,
                      )),
                      child: Column(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: t.background,
                              border: Border.all(
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey.withOpacity(0.3),
                                width: selected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text('字', style: TextStyle(color: t.text, fontSize: 20)),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t.label,
                            style: TextStyle(
                              fontSize: 12,
                              color: selected ? Theme.of(context).colorScheme.primary : null,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          const Divider(),

          // 开关项
          SwitchListTile(
            title: const Text('深色模式'),
            subtitle: const Text('全局界面深色'),
            value: settings.isDarkMode,
            onChanged: (v) => settingsService.update(settings.copyWith(isDarkMode: v)),
          ),
          SwitchListTile(
            title: const Text('翻页动画'),
            subtitle: const Text('翻页时显示过渡效果'),
            value: settings.pageTurnAnimation,
            onChanged: (v) => settingsService.update(settings.copyWith(pageTurnAnimation: v)),
          ),

          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '墨阅 v1.0.0\n纯本地离线阅读，书在手里，数据在你设备。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
