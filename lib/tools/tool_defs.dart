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
- Files the user attaches are saved under uploads/ in that folder. Binary attachments (zip, pdf, ...) are not inlined: unzip_file archives first, then use read_file, node_run or zip_file on the extracted files. JavaScript files (.js) can be executed with node_run — require local files by relative path, e.g. require('./uploads/project/lib/util.js').
- The node_run tool executes JavaScript in an embedded runtime with CommonJS modules. If a package is missing, install it with node_install first; remove unneeded packages with node_remove to save space.
- When the user attaches files, images travel as vision parts and text files are inlined; reference attachments by name.
- When you have enough information, stop calling tools and write the final answer in Markdown.
- Always answer in the same language the user writes in.
''';

/// Plan-first addendum (agent mode + planFirst): teaches the model to
/// start every task with a todo plan and to keep working through it until
/// every todo is completed — the loop reinforces this by nudging the model
/// whenever it tries to finish with an incomplete plan.
const String planFirstSystemPrompt = '''

# Task planning (todos)
- For every non-trivial task, ALWAYS begin by calling todo_write with a short plan (3-8 concise steps) before doing anything else.
- While working, keep exactly ONE todo marked in_progress. As soon as a step is truly done, call todo_write again to mark it completed and move the next one to in_progress. Add newly discovered work as extra todos.
- todo_write replaces the whole plan, so always send the complete updated list, not a diff.
- Keep working autonomously until EVERY todo is completed. Do not pause to ask for permission between steps.
- Write the final summary only after all todos are completed (or after explaining in the summary why a todo cannot be completed). Never stop halfway through the plan.
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
///
/// With [planFirst] the `todo_write` planning tool is included first so
/// the model writes a task plan before working (z.ai agent-mode style).
List<Map<String, dynamic>> buildAgentTools({bool planFirst = true}) =>
    <Map<String, dynamic>>[
      if (planFirst)
        _fn(
          'todo_write',
          'Create or update the todo list (task plan) for the current task. '
              'Send the FULL updated list every time — each item carries its '
              'status. Plan before starting work, then update progress after '
              'every completed step.',
          <String, dynamic>{
            'todos': <String, dynamic>{
              'type': 'array',
              'description':
                  'The complete updated todo list (max 50 items), in order.',
              'items': <String, dynamic>{
                'type': 'object',
                'properties': <String, dynamic>{
                  'content': <String, dynamic>{
                    'type': 'string',
                    'description': 'Short, imperative description of the step',
                  },
                  'status': <String, dynamic>{
                    'type': 'string',
                    'enum': <String>['pending', 'in_progress', 'completed'],
                    'description':
                        'pending = not started, in_progress = currently '
                        'working on, completed = fully done',
                  },
                },
                'required': <String>['content', 'status'],
              },
            },
          },
          <String>['todos'],
        ),
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
        'unzip_file',
        'Extract a .zip archive stored in the app documents folder (for example an uploaded file under uploads/) into a folder next to it. Returns the destination folder and the list of extracted files so their contents can be read or executed afterwards.',
        <String, dynamic>{
          'path': <String, dynamic>{
            'type': 'string',
            'description':
                'Relative path of the zip archive, e.g. uploads/1_project.zip',
          },
        },
        <String>['path'],
      ),
      _fn(
        'zip_file',
        'Compress a file or a whole folder from the app documents folder into a .zip archive created next to it. Returns the archive path.',
        <String, dynamic>{
          'path': <String, dynamic>{
            'type': 'string',
            'description': 'Relative path of the file or folder to compress',
          },
        },
        <String>['path'],
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
