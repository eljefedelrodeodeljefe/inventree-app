import "package:flutter/material.dart";
import "package:flutter_tabler_icons/flutter_tabler_icons.dart";

import "package:inventree/ai/ai_factory.dart";
import "package:inventree/ai/claude_service.dart";
import "package:inventree/ai/gemini_service.dart";
import "package:inventree/ai/openai_service.dart";
import "package:inventree/app_colors.dart";
import "package:inventree/l10.dart";
import "package:inventree/preferences.dart";

import "package:inventree/widget/dialogs.dart";
import "package:inventree/widget/snacks.dart";

class InvenTreeAISettingsWidget extends StatefulWidget {
  @override
  _InvenTreeAISettingsState createState() => _InvenTreeAISettingsState();
}

class _InvenTreeAISettingsState extends State<InvenTreeAISettingsWidget> {
  _InvenTreeAISettingsState();

  bool aiShowFeatures = true;
  bool aiEnabled = false;
  int aiProvider = AI_PROVIDER_CLAUDE;
  String aiApiKey = "";
  String aiModel = "";
  String aiForceTag = INV_AI_FORCE_TAG_DEFAULT;
  bool _testingConnection = false;
  bool _loadingModels = false;

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  /// Return the provider-specific preference key for API key.
  String get _apiKeyPref {
    switch (aiProvider) {
      case AI_PROVIDER_GEMINI:
        return INV_AI_GEMINI_API_KEY;
      case AI_PROVIDER_OPENAI:
        return INV_AI_OPENAI_API_KEY;
      default:
        return INV_AI_CLAUDE_API_KEY;
    }
  }

  /// Return the provider-specific preference key for model.
  String get _modelPref {
    switch (aiProvider) {
      case AI_PROVIDER_GEMINI:
        return INV_AI_GEMINI_MODEL;
      case AI_PROVIDER_OPENAI:
        return INV_AI_OPENAI_MODEL;
      default:
        return INV_AI_CLAUDE_MODEL;
    }
  }

  Future<void> loadSettings() async {
    final settings = InvenTreeSettingsManager();

    aiShowFeatures = await settings.getBool(INV_AI_SHOW_FEATURES, true);
    aiEnabled = await settings.getBool(INV_AI_ENABLED, false);
    aiProvider =
        await settings.getValue(INV_AI_PROVIDER, AI_PROVIDER_CLAUDE) as int;

    // One-time migration: copy legacy shared keys → Claude-specific keys
    final legacyKey = await settings.getValue(INV_AI_API_KEY, "") as String;
    final claudeKey =
        await settings.getValue(INV_AI_CLAUDE_API_KEY, "") as String;
    if (claudeKey.isEmpty && legacyKey.isNotEmpty) {
      await settings.setValue(INV_AI_CLAUDE_API_KEY, legacyKey);
      final legacyModel = await settings.getValue(INV_AI_MODEL, "") as String;
      if (legacyModel.isNotEmpty) {
        await settings.setValue(INV_AI_CLAUDE_MODEL, legacyModel);
      }
    }

    // Load provider-specific values
    aiApiKey = await settings.getValue(_apiKeyPref, "") as String;
    aiModel = await settings.getValue(_modelPref, "") as String;

    aiForceTag =
        await settings.getValue(INV_AI_FORCE_TAG, INV_AI_FORCE_TAG_DEFAULT)
            as String;

    if (mounted) {
      setState(() {});
    }
  }

  String _providerName(int provider) {
    switch (provider) {
      case AI_PROVIDER_CLAUDE:
        return L10().aiProviderClaude;
      case AI_PROVIDER_GEMINI:
        return L10().aiProviderGemini;
      case AI_PROVIDER_OPENAI:
        return L10().aiProviderOpenAI;
      default:
        return L10().aiUnknown;
    }
  }

  String get _defaultModelName {
    switch (aiProvider) {
      case AI_PROVIDER_GEMINI:
        return GeminiService.defaultModel;
      case AI_PROVIDER_OPENAI:
        return OpenAIService.defaultModel;
      default:
        return ClaudeService.defaultModel;
    }
  }

  String get _modelDisplay {
    if (aiModel.isEmpty) {
      return L10().aiModelDefaultLabel(_defaultModelName);
    }
    return aiModel;
  }

  Future<void> _selectModel(BuildContext context) async {
    if (aiApiKey.isEmpty) {
      showSnackIcon(L10().aiModelSelectFirst, success: false);
      return;
    }

    setState(() {
      _loadingModels = true;
    });

    try {
      if (aiProvider == AI_PROVIDER_GEMINI) {
        await _selectGeminiModel(context);
      } else if (aiProvider == AI_PROVIDER_OPENAI) {
        await _selectOpenAIModel(context);
      } else {
        await _selectClaudeModel(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingModels = false;
        });
      }
      String msg = e.toString();
      if (msg.startsWith("Exception: ")) {
        msg = msg.substring(11);
      }
      showSnackIcon(
        L10().aiModelLoadFailed,
        success: false,
        actionText: L10().details,
        onAction: () {
          showErrorDialog(L10().aiModelLoadFailed, description: msg);
        },
      );
    }
  }

  Future<void> _selectClaudeModel(BuildContext context) async {
    final models = await ClaudeService.listModels(aiApiKey);

    if (!mounted) return;

    setState(() {
      _loadingModels = false;
    });

    if (models.isEmpty) {
      showSnackIcon(L10().aiModelNoResults, success: false);
      return;
    }

    // Recommended model for multimodal: Sonnet 4.6 (best speed/intelligence)
    const String recommended = "claude-sonnet-4-6";

    List<Widget> items = [];
    for (final m in models) {
      String subtitle = m.id;
      if (m.id == recommended) {
        subtitle += "  (${L10().aiModelRecommendedVision})";
      }
      items.add(
        ListTile(
          title: Text(m.displayName),
          subtitle: Text(subtitle),
          leading: Icon(
            m.id == recommended ? TablerIcons.star_filled : TablerIcons.robot,
            color: m.id == recommended ? COLOR_WARNING : null,
          ),
        ),
      );
    }

    choiceDialog(
      L10().aiModelSelect,
      items,
      onSelected: (idx) async {
        final selected = models[idx as int];
        await InvenTreeSettingsManager().setValue(_modelPref, selected.id);
        if (mounted) {
          setState(() {
            aiModel = selected.id;
          });
        }
      },
    );
  }

  Future<void> _selectGeminiModel(BuildContext context) async {
    final models = await GeminiService.listModels(aiApiKey);

    if (!mounted) return;

    setState(() {
      _loadingModels = false;
    });

    if (models.isEmpty) {
      showSnackIcon(L10().aiModelNoResults, success: false);
      return;
    }

    const String recommended = "gemini-2.5-flash";

    List<Widget> items = [];
    for (final m in models) {
      String subtitle = m.name;
      if (m.name == recommended) {
        subtitle += "  (${L10().aiModelRecommendedVision})";
      }
      items.add(
        ListTile(
          title: Text(m.displayName),
          subtitle: Text(subtitle),
          leading: Icon(
            m.name == recommended ? TablerIcons.star_filled : TablerIcons.robot,
            color: m.name == recommended ? COLOR_WARNING : null,
          ),
        ),
      );
    }

    choiceDialog(
      L10().aiModelSelect,
      items,
      onSelected: (idx) async {
        final selected = models[idx as int];
        await InvenTreeSettingsManager().setValue(_modelPref, selected.name);
        if (mounted) {
          setState(() {
            aiModel = selected.name;
          });
        }
      },
    );
  }

  Future<void> _selectOpenAIModel(BuildContext context) async {
    final models = await OpenAIService.listModels(aiApiKey);

    if (!mounted) return;

    setState(() {
      _loadingModels = false;
    });

    if (models.isEmpty) {
      showSnackIcon(L10().aiModelNoResults, success: false);
      return;
    }

    const String recommended = "gpt-4o";

    List<Widget> items = [];
    for (final m in models) {
      String subtitle = m.id;
      if (m.id == recommended) {
        subtitle += "  (${L10().aiModelRecommendedVision})";
      }
      items.add(
        ListTile(
          title: Text(m.id),
          subtitle: Text(subtitle),
          leading: Icon(
            m.id == recommended ? TablerIcons.star_filled : TablerIcons.robot,
            color: m.id == recommended ? COLOR_WARNING : null,
          ),
        ),
      );
    }

    choiceDialog(
      L10().aiModelSelect,
      items,
      onSelected: (idx) async {
        final selected = models[idx as int];
        await InvenTreeSettingsManager().setValue(_modelPref, selected.id);
        if (mounted) {
          setState(() {
            aiModel = selected.id;
          });
        }
      },
    );
  }

  Future<void> _editForceTag(BuildContext context) async {
    final controller = TextEditingController(text: aiForceTag);

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(L10().aiForceInjectTag),
          content: SizedBox(
            width: 300,
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: L10().aiForceInjectTagHint,
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(TablerIcons.x, size: 18),
                  onPressed: () => controller.clear(),
                ),
              ),
            ),
          ),
          actions: <Widget>[
            MaterialButton(
              color: Colors.red,
              textColor: Colors.white,
              child: Text(L10().cancel),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            MaterialButton(
              color: Colors.green,
              textColor: Colors.white,
              child: Text(L10().save),
              onPressed: () async {
                String tag = controller.text.trim();
                await InvenTreeSettingsManager().setValue(
                  INV_AI_FORCE_TAG,
                  tag,
                );
                setState(() {
                  aiForceTag = tag;
                });
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _editApiKey(BuildContext context) async {
    final controller = TextEditingController(text: aiApiKey);

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(L10().aiApiKey),
          content: SizedBox(
            width: 300,
            child: TextField(
              controller: controller,
              obscureText: true,
              style: TextStyle(fontFamily: "monospace", letterSpacing: 2),
              decoration: InputDecoration(
                hintText: L10().aiApiKeyEnter,
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(TablerIcons.x, size: 18),
                  onPressed: () => controller.clear(),
                ),
              ),
            ),
          ),
          actions: <Widget>[
            MaterialButton(
              color: Colors.red,
              textColor: Colors.white,
              child: Text(L10().cancel),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            MaterialButton(
              color: Colors.green,
              textColor: Colors.white,
              child: Text(L10().save),
              onPressed: () async {
                String key = controller.text.trim();
                await InvenTreeSettingsManager().setValue(_apiKeyPref, key);
                setState(() {
                  aiApiKey = key;
                });
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _testConnection() async {
    if (_testingConnection) return;

    setState(() {
      _testingConnection = true;
    });

    try {
      final service = await AIServiceFactory.create();

      if (service == null) {
        showSnackIcon(L10().aiNotConfigured, success: false);
        return;
      }

      final bool result = await service.testConnection();

      if (result) {
        showSnackIcon(L10().aiConnectionSuccess, success: true);
      } else {
        showSnackIcon(L10().aiConnectionFailed, success: false);
      }
    } catch (e) {
      String msg = e.toString();
      if (msg.startsWith("Exception: ")) {
        msg = msg.substring(11);
      }
      showSnackIcon(
        L10().aiConnectionFailed,
        success: false,
        actionText: L10().details,
        onAction: () {
          showErrorDialog(L10().aiConnectionFailed, description: msg);
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _testingConnection = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String apiKeyDisplay = aiApiKey.isEmpty
        ? L10().aiApiKeyNotSet
        : "••••••••${aiApiKey.substring(aiApiKey.length < 4 ? 0 : aiApiKey.length - 4)}";

    return Scaffold(
      appBar: AppBar(
        title: Text(L10().aiSettings),
        backgroundColor: COLOR_APP_BAR,
      ),
      body: Container(
        child: ListView(
          children: [
            ListTile(
              title: Text(L10().aiShowFeatures),
              subtitle: Text(L10().aiShowFeaturesDetail),
              leading: Icon(TablerIcons.eye),
              trailing: Switch(
                value: aiShowFeatures,
                onChanged: (bool v) {
                  InvenTreeSettingsManager().setValue(INV_AI_SHOW_FEATURES, v);
                  setState(() {
                    aiShowFeatures = v;
                  });
                },
              ),
            ),
            ListTile(
              title: Text(L10().aiEnable),
              subtitle: Text(L10().aiEnableDetail),
              leading: Icon(TablerIcons.robot),
              trailing: Switch(
                value: aiEnabled,
                onChanged: (bool v) {
                  InvenTreeSettingsManager().setValue(INV_AI_ENABLED, v);
                  setState(() {
                    aiEnabled = v;
                  });
                },
              ),
            ),
            ListTile(
              title: Text(L10().aiProvider),
              subtitle: Text(_providerName(aiProvider)),
              leading: Icon(TablerIcons.brain),
              trailing: Icon(TablerIcons.chevron_right),
              onTap: () async {
                choiceDialog(
                  L10().aiProvider,
                  [
                    ListTile(
                      title: Text(L10().aiProviderClaude),
                      subtitle: Text(L10().aiProviderClaudeDetail),
                      leading: Icon(TablerIcons.robot),
                    ),
                    ListTile(
                      title: Text(L10().aiProviderGemini),
                      subtitle: Text(L10().aiProviderGeminiDetail),
                      leading: Icon(TablerIcons.robot),
                    ),
                    ListTile(
                      title: Text(L10().aiProviderOpenAI),
                      subtitle: Text(L10().aiProviderOpenAIDetail),
                      leading: Icon(TablerIcons.robot),
                    ),
                  ],
                  onSelected: (idx) async {
                    aiProvider = idx as int;
                    await InvenTreeSettingsManager().setValue(
                      INV_AI_PROVIDER,
                      aiProvider,
                    );
                    // Reload key/model for the new provider
                    final settings = InvenTreeSettingsManager();
                    aiApiKey =
                        await settings.getValue(_apiKeyPref, "") as String;
                    aiModel = await settings.getValue(_modelPref, "") as String;
                    if (mounted) {
                      setState(() {});
                    }
                  },
                );
              },
            ),
            ListTile(
              title: Text(L10().aiApiKey),
              subtitle: Text(apiKeyDisplay),
              leading: Icon(TablerIcons.key),
              trailing: Icon(TablerIcons.chevron_right),
              onTap: () {
                _editApiKey(context);
              },
            ),
            ListTile(
              title: Text(L10().aiModel),
              subtitle: Text(_modelDisplay),
              leading: _loadingModels
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(TablerIcons.cpu),
              trailing: Icon(TablerIcons.chevron_right),
              onTap: _loadingModels ? null : () => _selectModel(context),
            ),
            Divider(),
            ListTile(
              title: Text(L10().aiForceInjectTag),
              subtitle: Text(aiForceTag.isEmpty ? L10().aiNone : aiForceTag),
              leading: Icon(TablerIcons.tag),
              trailing: Icon(TablerIcons.chevron_right),
              onTap: () => _editForceTag(context),
            ),
            Divider(),
            ListTile(
              title: Text(L10().aiTestConnection),
              subtitle: Text(L10().aiTestConnectionDetail),
              leading: _testingConnection
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(TablerIcons.plug_connected, color: COLOR_ACTION),
              onTap: _testingConnection ? null : _testConnection,
            ),
          ],
        ),
      ),
    );
  }
}
