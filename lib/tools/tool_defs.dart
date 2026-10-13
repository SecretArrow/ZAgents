/// System prompt for agent mode.
const String agentSystemPrompt = '''
You are ZAgents, an autonomous AI agent running inside an Android app.
You can control a real embedded browser, manage local files, run JavaScript
with an embedded Node.js-style runtime, and work with files the user has
attached to their messages using the provided tools.

Guidelines:
- Work step by step. Call tools when they help you complete the task, observe each result, then continue.
- After opening or acting on a page, use browser_extract_text to read its content and browser_screenshot to capture important states for the user.
- Summarize page content in your own words instead of dumping raw text.
- If a tool fails, adapt: try another selector, a different URL, or explain the limitation to the user.
- File tools operate relative to the app's private documents folder. Use them for notes, reports, or data the user asks to store.
- The node_run tool executes JavaScript in an embedded runtime with CommonJS modules. If a package is missing, install it with node_install first; remove unneeded packages with node_remove to save space.
- When the user attaches files, they are included in their message (images as vision parts, text files inline, binaries as metadata only). Reference them by name.
- When you have enough information, stop calling tools and write the final answer in Markdown.
- Always answer in the same language the user writes in.
''';

Map<String, dynamic> _fn(
  String name,
  String description,
  Map<String, dynamic> properties,
  List<String> required,
) => <String, dynamic>{
  'type': 'function',
  'function': <String, dynamic>{
    'name': name,
    'description': description,
    'parameters': <String, dynamic>{
      'type': 'object',
      'properties': properties,
      'required': required,
    },
  },
};

/// OpenAI-compatible tool schemas exposed to the model in agent mode.
List<Map<String, dynamic>> buildAgentTools() => <Map<String, dynamic>>[
  _fn(
    'browser_navigate',
    'Open a URL in the embedded browser. Returns page title, URL and a text preview.',
    <String, dynamic>{
      'url': <String, dynamic>{
        'type': 'string',
        'description': 'Full URL, e.g. https://example.com',
      },
    },
    <String>['url'],
  ),
  _fn(
    'browser_click',
    'Click an element in the current page, either by CSS selector or by visible text.',
    <String, dynamic>{
      'selector': <String, dynamic>{
        'type': 'string',
        'description': 'CSS selector of the element',
      },
      'text': <String, dynamic>{
        'type': 'string',
        'description': 'Visible text to search for (link/button label)',
      },
    },
    const <String>[],
  ),
  _fn(
    'browser_type',
    'Type text into an input/textarea/contenteditable, by CSS selector or the currently focused element.',
    <String, dynamic>{
      'text': <String, dynamic>{
        'type': 'string',
        'description': 'Text to type',
      },
      'selector': <String, dynamic>{
        'type': 'string',
        'description': 'CSS selector; omit to use the focused element',
      },
      'clear': <String, dynamic>{
        'type': 'boolean',
        'description': 'Clear existing value first (default true)',
      },
    },
    <String>['text'],
  ),
  _fn('browser_scroll', 'Scroll the page up or down.', <String, dynamic>{
    'direction': <String, dynamic>{
      'type': 'string',
      'enum': <String>['up', 'down'],
    },
    'amount': <String, dynamic>{
      'type': 'integer',
      'description': 'Pixels to scroll (default 800)',
    },
  }, const <String>[]),
  _fn(
    'browser_screenshot',
    'Capture a screenshot of the current page. The image is shown to the user in the chat.',
    <String, dynamic>{},
    const <String>[],
  ),
  _fn(
    'browser_extract_text',
    'Extract readable text from the current page for analysis.',
    <String, dynamic>{
      'maxLength': <String, dynamic>{
        'type': 'integer',
        'description': 'Max characters to return (default 8000)',
      },
    },
    const <String>[],
  ),
  _fn(
    'run_js',
    'Evaluate arbitrary JavaScript in the page context. Returns the serialized result.',
    <String, dynamic>{
      'code': <String, dynamic>{
        'type': 'string',
        'description': 'JavaScript source to run',
      },
    },
    <String>['code'],
  ),
  _fn(
    'read_file',
    'Read a text file from the app documents folder.',
    <String, dynamic>{
      'path': <String, dynamic>{
        'type': 'string',
        'description': 'Relative path, e.g. notes/todo.txt',
      },
    },
    <String>['path'],
  ),
  _fn(
    'write_file',
    'Create or overwrite a text file in the app documents folder (parent folders are created).',
    <String, dynamic>{
      'path': <String, dynamic>{
        'type': 'string',
        'description': 'Relative path',
      },
      'content': <String, dynamic>{
        'type': 'string',
        'description': 'File content',
      },
    },
    <String>['path', 'content'],
  ),
  _fn(
    'node_run',
    'Run JavaScript code in the embedded Node.js-style runtime. Supports CommonJS modules (require) from installed packages, console output, an fs-like file bridge and fetch. Use it for data processing, parsing, calculations and automation the other tools cannot do.',
    <String, dynamic>{
      'code': <String, dynamic>{
        'type': 'string',
        'description': 'JavaScript source. The final expression is the return value; use console.log for progress.',
      },
    },
    <String>['code'],
  ),
  _fn(
    'node_install',
    'Install an npm package (and its runtime dependencies) into the embedded runtime so node_run can require it. Pure-JavaScript packages only.',
    <String, dynamic>{
      'package': <String, dynamic>{
        'type': 'string',
        'description': 'Package name, e.g. lodash or dayjs',
      },
      'version': <String, dynamic>{
        'type': 'string',
        'description': 'Optional exact version (default latest)',
      },
    },
    <String>['package'],
  ),
  _fn(
    'node_remove',
    'Remove an installed npm package from the embedded runtime when it is no longer needed.',
    <String, dynamic>{
      'package': <String, dynamic>{
        'type': 'string',
        'description': 'Package name to remove',
      },
    },
    <String>['package'],
  ),
];
