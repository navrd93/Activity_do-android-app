import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

/// Increased contrast theme colors with more saturated values.
final Map<String, Color> lightThemeColors = {
  'purple': Colors.deepPurple[400]!,
  'red': Colors.red[400]!,
  'green': Colors.green[400]!,
  'yellow': Colors.yellow[400]!,
};

final Map<String, Color> darkThemeColors = {
  'purple': Colors.deepPurple[900]!,
  'red': Colors.red[900]!,
  'green': Colors.green[900]!,
  'yellow': Colors.yellow[900]!,
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  bool isDark = prefs.getBool('isDarkTheme') ?? false;
  String savedThemeName = prefs.getString('themeName') ?? "purple";
  runApp(TodoApp(isDark: isDark, savedThemeName: savedThemeName));
}

/// ThemeNotifier controls dark/light mode and theme color.
class ThemeNotifier extends ChangeNotifier {
  bool isDark;
  String themeName;
  ThemeNotifier({required this.isDark, required this.themeName});

  void toggleTheme(bool val) {
    isDark = val;
    saveTheme();
    notifyListeners();
  }

  void updateTheme(String newTheme) {
    themeName = newTheme;
    saveTheme();
    notifyListeners();
  }

  Future<void> saveTheme() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkTheme', isDark);
    await prefs.setString('themeName', themeName);
  }
}

/// Task model.
class Task {
  String id, text, category, dueDate, dueTime, recurring, notes;
  bool completed;
  int priority; // 1=High, 2=Medium, 3=Low
  List<String> participants;
  bool notifyBefore; // Notification 10 mins before

  Task({
    required this.text,
    this.id = '',
    this.completed = false,
    this.priority = 2,
    this.category = 'Personal',
    this.dueDate = '',
    this.dueTime = '',
    this.recurring = 'none',
    this.notes = '',
    this.participants = const [],
    this.notifyBefore = false,
  }) {
    id = id.isEmpty ? DateTime.now().millisecondsSinceEpoch.toString() : id;
    dueDate = dueDate.isEmpty
        ? DateFormat('yyyy-MM-dd').format(DateTime.now())
        : dueDate;
  }

  String getPriorityText() =>
      {1: 'High', 2: 'Medium', 3: 'Low'}[priority] ?? '';

  Color getPriorityColor(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    if (priority == 1) {
      return isDark ? Colors.red.shade700 : Colors.red;
    } else if (priority == 2) {
      return isDark ? Colors.yellow.shade700 : Colors.amber.shade700;
    } else if (priority == 3) {
      return isDark ? Colors.green.shade700 : Colors.green;
    }
    return Colors.grey;
  }

  Color getTextColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black;

  String toJson() => jsonEncode({
        'id': id,
        'text': text,
        'completed': completed,
        'priority': priority,
        'category': category,
        'dueDate': dueDate,
        'dueTime': dueTime,
        'recurring': recurring,
        'notes': notes,
        'participants': participants,
        'notifyBefore': notifyBefore,
      });

  static Task fromJson(String jsonStr) {
    var d = jsonDecode(jsonStr);
    return Task(
      id: d['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      text: d['text'],
      completed: d['completed'],
      priority: d['priority'],
      category: d['category'],
      dueDate: d['dueDate'],
      dueTime: d['dueTime'],
      recurring: d['recurring'] ?? 'none',
      notes: d['notes'] ?? '',
      participants: List<String>.from(d['participants'] ?? []),
      notifyBefore: d['notifyBefore'] ?? false,
    );
  }

  /// Returns next due date based on recurring type.
  String nextDueDate() {
    DateTime current;
    try {
      current = DateFormat('yyyy-MM-dd').parse(dueDate);
    } catch (_) {
      current = DateTime.now();
    }
    DateTime next;
    if (recurring == 'daily') {
      next = current.add(const Duration(days: 1));
    } else if (recurring == 'monthly') {
      next = DateTime(current.year, current.month + 1, current.day);
    } else if (recurring == 'yearly') {
      next = DateTime(current.year + 1, current.month, current.day);
    } else {
      next = current;
    }
    return DateFormat('yyyy-MM-dd').format(next);
  }
}

/// Represents an occurrence of a task.
class TaskOccurrence {
  final Task task;
  final DateTime occurrenceDate;
  TaskOccurrence({required this.task, required this.occurrenceDate});
}

/// TaskProvider now also holds the selectedCity and temperature unit.
class TaskProvider extends ChangeNotifier {
  List<Task> tasks = [];
  List<Task> completedTasks = [];
  List<String> filterCategories = ['All'];
  String sortOption = "all";
  String sortBy = 'Priority',
      taskCategory = 'Personal',
      profileIcon = '👤',
      userName = '';
  List<String> customCategories = ['Personal', 'Work', 'Fitness', 'Hobbies'];
  bool viewingCompleted = false;
  bool showCompletedTasks = false;
  bool hasLaunchedBefore = false;
  Map<String, String> activityCategories = {
    'Jogging': '🏃',
    'Music': '🎸',
    'Painting': '🎨',
    'Party': '🥳',
    'Shopping': '🛍️',
    'Gaming': '🎮',
    'Writing': '✍️',
    'Trading': '💹',
    'Loving': '❤️',
    'Working': '💼',
    'Reading': '📚',
    'Drink': '🍹',
  };
  String lastUsedActivityEmoji = "";
  bool globalNotificationsEnabled = true;
  
  // New settings fields.
  String selectedCity = "London";
  String tempUnit = "C"; // "C" for Celsius and "F" for Fahrenheit

  TaskProvider() {
    loadData();
    Timer.periodic(const Duration(minutes: 1), (_) {
      notifyListeners();
    });
  }

  Future<void> loadData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? taskList = prefs.getStringList('tasks');
    if (taskList != null) {
      tasks = taskList.map((t) => Task.fromJson(t)).toList();
    }
    List<String>? completedList = prefs.getStringList('completedTasks');
    if (completedList != null) {
      completedTasks = completedList.map((t) => Task.fromJson(t)).toList();
    }
    customCategories =
        prefs.getStringList('customCategories') ?? customCategories;
    profileIcon = prefs.getString('profileIcon') ?? profileIcon;
    userName = prefs.getString('userName') ?? userName;
    taskCategory = prefs.getString('taskCategory') ?? taskCategory;
    showCompletedTasks = prefs.getBool('showCompletedTasks') ?? false;
    globalNotificationsEnabled =
        prefs.getBool('globalNotificationsEnabled') ?? true;
    hasLaunchedBefore = prefs.getBool('hasLaunchedBefore') ?? false;
    selectedCity = prefs.getString('selectedCity') ?? "London";
    tempUnit = prefs.getString('tempUnit') ?? "C";
    notifyListeners();
  }

  Future<void> saveData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('tasks', tasks.map((t) => t.toJson()).toList());
    await prefs.setStringList(
        'completedTasks', completedTasks.map((t) => t.toJson()).toList());
    await prefs.setStringList('customCategories', customCategories);
    await prefs.setString('profileIcon', profileIcon);
    await prefs.setString('taskCategory', taskCategory);
    await prefs.setString('userName', userName);
    await prefs.setBool('globalNotificationsEnabled', globalNotificationsEnabled);
    await prefs.setBool('showCompletedTasks', showCompletedTasks);
    await prefs.setBool('hasLaunchedBefore', hasLaunchedBefore);
    await prefs.setString('selectedCity', selectedCity);
    await prefs.setString('tempUnit', tempUnit);
  }

  // Mark the app as launched.
  void markLaunched() {
    if (!hasLaunchedBefore) {
      hasLaunchedBefore = true;
      saveData();
      notifyListeners();
    }
  }

  void clearCompletedTasks() {
    completedTasks.clear();
    saveData();
    notifyListeners();
  }

  // Returns active task occurrences.
  List<TaskOccurrence> getUniqueTaskOccurrences() {
    List<TaskOccurrence> allOccurrences = [];
    DateTime now = DateTime.now();
    DateTime currentDate = DateTime(now.year, now.month, now.day);
    DateTime endDate = currentDate.add(const Duration(days: 365));
    DateFormat formatter = DateFormat('yyyy-MM-dd');
    List<Task> filteredTasks;
    if (filterCategories.contains("All")) {
      filteredTasks = tasks;
    } else {
      filteredTasks =
          tasks.where((t) => filterCategories.contains(t.category)).toList();
    }
    for (Task task in filteredTasks) {
      DateTime due;
      try {
        due = formatter.parse(task.dueDate);
      } catch (_) {
        continue;
      }
      DateTime taskDate = DateTime(due.year, due.month, due.day);
      if (task.recurring == 'none') {
        if (!taskDate.isBefore(currentDate) && !taskDate.isAfter(endDate))
          allOccurrences.add(TaskOccurrence(task: task, occurrenceDate: taskDate));
      } else if (task.recurring == 'daily') {
        DateTime occurrence = taskDate.isBefore(currentDate) ? currentDate : taskDate;
        if (!occurrence.isAfter(endDate))
          allOccurrences.add(TaskOccurrence(task: task, occurrenceDate: occurrence));
      } else if (task.recurring == 'monthly') {
        DateTime occurrence = taskDate;
        if (occurrence.isBefore(currentDate)) {
          int monthsToAdd = ((currentDate.year - occurrence.year) * 12 +
              currentDate.month -
              occurrence.month);
          occurrence = DateTime(occurrence.year, occurrence.month + monthsToAdd, occurrence.day);
          if (occurrence.isBefore(currentDate))
            occurrence = DateTime(occurrence.year, occurrence.month + 1, occurrence.day);
        }
        if (!occurrence.isAfter(endDate))
          allOccurrences.add(TaskOccurrence(task: task, occurrenceDate: occurrence));
      } else if (task.recurring == 'yearly') {
        DateTime occurrence = taskDate;
        if (occurrence.isBefore(currentDate)) {
          int yearsToAdd = currentDate.year - occurrence.year;
          occurrence = DateTime(occurrence.year + yearsToAdd, occurrence.month, occurrence.day);
          if (occurrence.isBefore(currentDate))
            occurrence = DateTime(occurrence.year + 1, occurrence.month, occurrence.day);
        }
        if (!occurrence.isAfter(endDate))
          allOccurrences.add(TaskOccurrence(task: task, occurrenceDate: occurrence));
      }
    }
    Map<String, TaskOccurrence> unique = {};
    for (TaskOccurrence occ in allOccurrences) {
      if (!unique.containsKey(occ.task.id) ||
          occ.occurrenceDate.isBefore(unique[occ.task.id]!.occurrenceDate))
        unique[occ.task.id] = occ;
    }
    List<TaskOccurrence> uniqueOccurrences = unique.values.toList();
    uniqueOccurrences.sort((a, b) => a.occurrenceDate.compareTo(b.occurrenceDate));
    return uniqueOccurrences;
  }

  void addTask(Task t) {
    tasks.add(t);
    lastUsedActivityEmoji = activityCategories[t.category] ?? "";
    saveData();
    notifyListeners();
  }

  void updateTask(Task updatedTask) {
    int index = tasks.indexWhere((t) => t.id == updatedTask.id);
    if (index != -1) {
      tasks[index] = updatedTask;
      saveData();
      notifyListeners();
    }
  }

  void deleteTask(Task t) {
    tasks.removeWhere((element) => element.id == t.id);
    completedTasks.add(t);
    saveData();
    notifyListeners();
  }

  // Modified toggleTaskCompletion:
  // For recurring tasks, when marked complete for today, add an entry to completedTasks (for histogram)
  // and then update the task's dueDate to the next due date.
  void toggleTaskCompletion(Task t) {
    if (t.recurring != 'none') {
      Task completedRecord = Task(
        text: t.text,
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        completed: true,
        priority: t.priority,
        category: t.category,
        dueDate: t.dueDate,
        dueTime: t.dueTime,
        recurring: t.recurring,
        notes: t.notes,
        participants: t.participants,
        notifyBefore: t.notifyBefore,
      );
      completedTasks.add(completedRecord);
      t.dueDate = t.nextDueDate();
      saveData();
      notifyListeners();
    } else {
      if (!t.completed) {
        t.completed = true;
        tasks.remove(t);
        completedTasks.add(t);
        saveData();
        notifyListeners();
      }
    }
  }

  void removeCompletedTask(Task t) {
    completedTasks.removeWhere((element) => element.id == t.id);
    saveData();
    notifyListeners();
  }

  void setProfileIcon(String icon) {
    profileIcon = icon;
    saveData();
    notifyListeners();
  }

  void setProfileName(String name) {
    userName = name;
    saveData();
    notifyListeners();
  }
  
  // Methods to update new settings.
  void updateSelectedCity(String city) {
    selectedCity = city;
    saveData();
    notifyListeners();
  }
  
  void toggleTempUnit() {
    tempUnit = tempUnit == "C" ? "F" : "C";
    saveData();
    notifyListeners();
  }
  
  void setTempUnit(String unit) {
    tempUnit = unit;
    saveData();
    notifyListeners();
  }
  
  void toggleShowCompleted(bool val) {
    showCompletedTasks = val;
    saveData();
    notifyListeners();
  }
}

/// WeatherPillWidget shows a round weather icon with a dynamic weather emoji and temperature.
/// When tapped, it expands to show detailed weather info.
/// It uses the selected city and temperature unit from TaskProvider and refetches weather when either changes.
class WeatherPillWidget extends StatefulWidget {
  const WeatherPillWidget({Key? key}) : super(key: key);
  @override
  _WeatherPillWidgetState createState() => _WeatherPillWidgetState();
}

class _WeatherPillWidgetState extends State<WeatherPillWidget>
    with SingleTickerProviderStateMixin {
  bool isExpanded = false;
  late AnimationController _controller;
  String weatherEmoji = "❓";
  String weatherDesc = "";
  double temperature = 0.0;
  bool loading = true;

  String lastCity = "";
  String lastTempUnit = "";

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    final provider = Provider.of<TaskProvider>(context, listen: false);
    lastCity = provider.selectedCity;
    lastTempUnit = provider.tempUnit;
    fetchWeather();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<TaskProvider>(context);
    if (provider.selectedCity != lastCity || provider.tempUnit != lastTempUnit) {
      lastCity = provider.selectedCity;
      lastTempUnit = provider.tempUnit;
      fetchWeather();
    }
  }

  Future<void> fetchWeather() async {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    String city = taskProvider.selectedCity;
    String unitParam = taskProvider.tempUnit == "C" ? "metric" : "imperial";
    const apiKey = "41576279633df7e2527e6b2dd42aa054";
    final url =
        "https://api.openweathermap.org/data/2.5/weather?q=$city&appid=$apiKey&units=$unitParam";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          weatherDesc = data['weather'][0]['description'];
          temperature = data['main']['temp'].toDouble();
          if (weatherDesc.contains("cloud", 0)) {
            weatherEmoji = "☁️";
          } else if (weatherDesc.contains("rain", 0)) {
            weatherEmoji = "🌧";
          } else if (weatherDesc.contains("snow", 0)) {
            weatherEmoji = "❄️";
          } else if (weatherDesc.contains("clear", 0)) {
            weatherEmoji = "☀️";
          } else if (weatherDesc.contains("wind", 0)) {
            weatherEmoji = "💨";
          } else {
            weatherEmoji = "🌤";
          }
          loading = false;
        });
      } else {
        setState(() {
          weatherDesc = "Unavailable";
          weatherEmoji = "❓";
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        weatherDesc = "Error";
        weatherEmoji = "❓";
        loading = false;
      });
    }
  }

  void toggleExpansion() {
    if (isExpanded) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    setState(() {
      isExpanded = !isExpanded;
    });
  }

  Widget buildCollapsed() {
    return Container(
      width: 50,
      height: 50,
      decoration: const BoxDecoration(
        color: Colors.black,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(weatherEmoji, style: const TextStyle(fontSize: 28, color: Colors.white)),
              Text("${temperature.toStringAsFixed(0)}°${Provider.of<TaskProvider>(context).tempUnit}",
                  style: const TextStyle(fontSize: 12, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildExpanded() {
    return Container(
      width: 180,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(25),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(weatherEmoji, style: const TextStyle(fontSize: 28, color: Colors.white)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Provider.of<TaskProvider>(context).selectedCity,
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                Text(weatherDesc,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text("${temperature.toStringAsFixed(0)}°${Provider.of<TaskProvider>(context).tempUnit}",
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const SizedBox.shrink();
    return GestureDetector(
      onTap: toggleExpansion,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: isExpanded ? buildExpanded() : buildCollapsed(),
      ),
    );
  }
}

/// StatsDialog displays a histogram of completed activities.
class StatsDialog extends StatefulWidget {
  const StatsDialog({Key? key}) : super(key: key);
  @override
  _StatsDialogState createState() => _StatsDialogState();
}

class _StatsDialogState extends State<StatsDialog> {
  String filterOption = "Daily";

  final Map<String, Color> activityColors = {
    'Jogging': Colors.green,
    'Music': Colors.blue,
    'Painting': Colors.orange,
    'Party': Colors.purple,
    'Shopping': Colors.red,
    'Gaming': Colors.teal,
    'Writing': Colors.brown,
    'Trading': Colors.indigo,
    'Loving': Colors.pink,
    'Working': Colors.cyan,
    'Reading': Colors.amber,
    'Drink': Colors.lime,
  };

  List<Task> _filterCompletedTasks(List<Task> tasks) {
    DateTime now = DateTime.now();
    return tasks.where((task) {
      DateTime taskDate;
      try {
        taskDate = DateFormat('yyyy-MM-dd').parse(task.dueDate);
      } catch (_) {
        return false;
      }
      if (filterOption == "Daily") {
        return taskDate.year == now.year &&
            taskDate.month == now.month &&
            taskDate.day == now.day;
      } else if (filterOption == "Weekly") {
        int currentWeek = int.parse(DateFormat("w").format(now));
        int taskWeek = int.parse(DateFormat("w").format(taskDate));
        return taskDate.year == now.year && taskWeek == currentWeek;
      } else if (filterOption == "Monthly") {
        return taskDate.year == now.year && taskDate.month == now.month;
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TaskProvider>(context);
    List<Task> filteredTasks = _filterCompletedTasks(provider.completedTasks);
    Map<String, int> activityCounts = {};
    for (Task task in filteredTasks) {
      String category = task.category;
      activityCounts[category] = (activityCounts[category] ?? 0) + 1;
    }
    final activeActivities = provider.activityCategories.keys
        .where((activity) => (activityCounts[activity] ?? 0) > 0)
        .toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Filter:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: filterOption,
                  items: const [
                    DropdownMenuItem(value: "Daily", child: Text("Daily")),
                    DropdownMenuItem(value: "Weekly", child: Text("Weekly")),
                    DropdownMenuItem(value: "Monthly", child: Text("Monthly")),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        filterOption = value;
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: activeActivities.isEmpty
                    ? const Center(child: Text("No activities found"))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: activeActivities.map((activity) {
                          int count = activityCounts[activity] ?? 0;
                          const double maxBarHeight = 100;
                          double barHeight = (count >= 10)
                              ? maxBarHeight
                              : (count / 10) * maxBarHeight;
                          
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (count < 10)
                                    Text("$count", style: const TextStyle(fontWeight: FontWeight.bold))
                                  else
                                    const SizedBox(height: 16),
                                  Container(
                                    height: barHeight,
                                    width: 24,
                                    decoration: BoxDecoration(
                                      color: activityColors[activity] ?? Colors.grey,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: count >= 10
                                        ? Center(
                                            child: Text("$count", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)))
                                        : null,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(provider.activityCategories[activity] ?? "", style: const TextStyle(fontSize: 20)),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text("Close"),
            )
          ],
        ),
      ),
    );
  }
}

/// CompletedActivitiesScreen shows only completed tasks.
class CompletedActivitiesScreen extends StatelessWidget {
  const CompletedActivitiesScreen({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TaskProvider>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Completed Activities"),
      ),
      body: provider.completedTasks.isNotEmpty
          ? ListView.builder(
              itemCount: provider.completedTasks.length,
              itemBuilder: (context, index) {
                final task = provider.completedTasks[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(provider.activityCategories[task.category] ?? ''),
                  ),
                  title: Text(task.text, style: const TextStyle(decoration: TextDecoration.lineThrough)),
                  subtitle: const Text("Completed"),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      provider.removeCompletedTask(task);
                    },
                  ),
                );
              },
            )
          : const Center(child: Text("No Completed Activities")),
    );
  }
}

/// DynamicIslandWidget displays a small circle with a stats icon.
class DynamicIslandWidget extends StatefulWidget {
  const DynamicIslandWidget({Key? key}) : super(key: key);
  @override
  _DynamicIslandWidgetState createState() => _DynamicIslandWidgetState();
}

class _DynamicIslandWidgetState extends State<DynamicIslandWidget> with TickerProviderStateMixin {
  bool isExpanded = false;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void toggleExpansion() {
    if (isExpanded) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    setState(() {
      isExpanded = !isExpanded;
    });
  }

  void collapse() {
    if (isExpanded) {
      _controller.reverse();
      setState(() {
        isExpanded = false;
      });
    }
  }

  void _openStatsDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) => const StatsDialog(),
    );
  }

  void _openCalendarDialog() {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const FullCalendarModal()));
  }

  void _openQuickNoteDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => const QuickNoteDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: toggleExpansion,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          constraints: BoxConstraints(minWidth: isExpanded ? 150 : 50),
          height: isExpanded ? 70 : 50,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(isExpanded ? 25 : 50),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 4,
                offset: const Offset(2, 2),
              )
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: isExpanded
                ? [
                    IconButton(icon: const Icon(Icons.bar_chart, color: Colors.white), onPressed: _openStatsDialog),
                    IconButton(icon: const Icon(Icons.calendar_today, color: Colors.white), onPressed: _openCalendarDialog),
                    IconButton(icon: const Icon(Icons.note_add, color: Colors.white), onPressed: _openQuickNoteDialog),
                  ]
                : [const Center(child: Icon(Icons.bar_chart, color: Colors.white, size: 28))],
          ),
        ),
      ),
    );
  }
}

/// QuickNoteDialog with persistent draft and saved notes.
class QuickNoteDialog extends StatefulWidget {
  const QuickNoteDialog({Key? key}) : super(key: key);
  @override
  _QuickNoteDialogState createState() => _QuickNoteDialogState();
}

class _QuickNoteDialogState extends State<QuickNoteDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _noteController = TextEditingController();
  final List<String> _savedNotes = [];
  final String draftKey = "quick_note_draft";
  final String editingIndexKey = "quick_note_edit_index";
  int? _editingNoteIndex;

  int _wordCount(String text) {
    if (text.isEmpty) return 0;
    return text.trim().split(RegExp(r'\s+')).length;
  }

  String _getSummary(String note) {
    List<String> words = note.trim().split(RegExp(r'\s+'));
    if (words.length <= 5) return note;
    return words.sublist(0, 5).join(" ") + "...";
  }

  void _loadSavedNotes() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? notes = prefs.getStringList("quick_notes");
    if (notes != null) {
      setState(() {
        _savedNotes.clear();
        _savedNotes.addAll(notes);
      });
    }
  }

  void _persistSavedNotes() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList("quick_notes", _savedNotes);
  }

  void _loadDraft() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? draft = prefs.getString(draftKey);
    if (draft != null && draft.isNotEmpty) {
      setState(() {
        _noteController.text = draft;
      });
    }
    int? idx = prefs.getInt(editingIndexKey);
    if (idx != null) {
      setState(() {
        _editingNoteIndex = idx;
      });
    }
  }

  void _persistDraft(String text) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(draftKey, text);
  }

  void _persistEditingIndex(int? index) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (index != null) {
      await prefs.setInt(editingIndexKey, index);
    } else {
      await prefs.remove(editingIndexKey);
    }
  }

  void _clearDraft() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(draftKey);
    await prefs.remove(editingIndexKey);
  }

  void _saveNote() {
    if (_noteController.text.trim().isNotEmpty && _wordCount(_noteController.text) <= 5000) {
      setState(() {
        _savedNotes.add(_noteController.text.trim());
        _noteController.clear();
        _editingNoteIndex = null;
      });
      _persistSavedNotes();
      _clearDraft();
    }
  }

  void _updateNote() {
    if (_editingNoteIndex != null && _noteController.text.trim().isNotEmpty && _wordCount(_noteController.text) <= 5000) {
      setState(() {
        _savedNotes[_editingNoteIndex!] = _noteController.text.trim();
        _noteController.clear();
        _editingNoteIndex = null;
      });
      _persistSavedNotes();
      _clearDraft();
    }
  }

  void _deleteNote() {
    if (_editingNoteIndex != null) {
      setState(() {
        _savedNotes.removeAt(_editingNoteIndex!);
        _noteController.clear();
        _editingNoteIndex = null;
      });
      _persistSavedNotes();
      _clearDraft();
    }
  }

  void _loadSavedNote(int index) {
    setState(() {
      _noteController.text = _savedNotes[index];
      _editingNoteIndex = index;
      _persistEditingIndex(_editingNoteIndex);
      _tabController.index = 0;
    });
  }

  void _deleteNoteFromList(int index) {
    setState(() {
      if (_editingNoteIndex != null && _editingNoteIndex == index) {
        _editingNoteIndex = null;
        _noteController.clear();
        _clearDraft();
      }
      _savedNotes.removeAt(index);
    });
    _persistSavedNotes();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    _loadSavedNotes();
    _loadDraft();
    _noteController.addListener(() {
      _persistDraft(_noteController.text);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark ? Colors.grey[800] : Colors.grey[300];
    final bool isEditing = _editingNoteIndex != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 400,
        height: 250,
        color: theme.cardColor,
        child: Column(
          children: [
            Material(
              color: theme.cardColor,
              child: TabBar(
                controller: _tabController,
                labelColor: isDark ? Colors.white : theme.primaryColor,
                unselectedLabelColor: isDark ? Colors.grey[400] : Colors.black,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
                indicatorColor: isDark ? Colors.white : theme.primaryColor,
                tabs: const [
                  Tab(text: "Note"),
                  Tab(text: "Saved Notes"),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _noteController,
                            maxLines: null,
                            expands: true,
                            decoration: InputDecoration(
                              hintText: "Enter your quick note (max 5000 words)",
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: isEditing
                              ? [
                                  ElevatedButton(onPressed: _updateNote, child: const Text("Update")),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: _deleteNote,
                                    icon: const Icon(Icons.delete),
                                    label: const Text("Delete"),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  ),
                                ]
                              : [ElevatedButton(onPressed: _saveNote, child: const Text("Save"))],
                        )
                      ],
                    ),
                  ),
                  _savedNotes.isNotEmpty
                      ? ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _savedNotes.length,
                          itemBuilder: (context, index) {
                            String summary = _getSummary(_savedNotes[index]);
                            return Card(
                              color: cardColor,
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 2,
                              child: ListTile(
                                title: Text(summary, style: theme.textTheme.bodyMedium),
                                trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteNoteFromList(index)),
                                onTap: () => _loadSavedNote(index),
                              ),
                            );
                          },
                        )
                      : Center(child: Text("No saved notes", style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// SavedNotesScreen displays all the saved notes.
class SavedNotesScreen extends StatelessWidget {
  final List<String> savedNotes;
  const SavedNotesScreen({Key? key, required this.savedNotes}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Saved Notes"), backgroundColor: theme.appBarTheme.backgroundColor),
      body: Container(
        padding: const EdgeInsets.all(16),
        child: savedNotes.isNotEmpty
            ? ListView.builder(
                itemCount: savedNotes.length,
                itemBuilder: (context, index) {
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 2,
                    child: Padding(padding: const EdgeInsets.all(8.0), child: Text(savedNotes[index], style: theme.textTheme.bodyMedium)),
                  );
                },
              )
            : Center(child: Text("No saved notes", style: theme.textTheme.bodyMedium)),
      ),
    );
  }
}

/// TodoApp widget.
class TodoApp extends StatefulWidget {
  final bool isDark;
  final String savedThemeName;
  const TodoApp({Key? key, required this.isDark, required this.savedThemeName}) : super(key: key);
  @override
  State<TodoApp> createState() => TodoAppState();
}

class TodoAppState extends State<TodoApp> {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TaskProvider()),
        ChangeNotifierProvider(create: (_) => ThemeNotifier(isDark: widget.isDark, themeName: widget.savedThemeName)),
      ],
      child: Consumer<ThemeNotifier>(
        builder: (context, themeNotifier, _) {
          final lightSeed = lightThemeColors[themeNotifier.themeName]!;
          final darkSeed = darkThemeColors[themeNotifier.themeName]!;
          return MaterialApp(
            title: 'Wacana Todo',
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: lightSeed, brightness: Brightness.light),
              appBarTheme: AppBarTheme(
                centerTitle: true,
                backgroundColor: lightSeed,
                elevation: 4,
                toolbarHeight: 80,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
              ),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: darkSeed, brightness: Brightness.dark),
              appBarTheme: AppBarTheme(
                centerTitle: true,
                backgroundColor: darkSeed,
                elevation: 4,
                toolbarHeight: 80,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
              ),
            ),
            themeMode: themeNotifier.isDark ? ThemeMode.dark : ThemeMode.light,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}

/// HomeScreen displays header, tasks, and includes DynamicIslandWidget.
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);
  @override
  _HomeScreenState createState() => _HomeScreenState();
}
  
class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<_DynamicIslandWidgetState> _dynamicIslandKey = GlobalKey<_DynamicIslandWidgetState>();

  @override
  void initState() {
    super.initState();
    Provider.of<TaskProvider>(context, listen: false).markLaunched();
  }

  void _showAddActivityModal() {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AddActivitySheet()));
  }

  void _showFilterOptions() {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const FilterOptionsSheet()));
  }
  
  @override
  Widget build(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context);
    return GestureDetector(
      onTapDown: (details) {
        final RenderBox? box = _dynamicIslandKey.currentContext?.findRenderObject() as RenderBox?;
        if (box != null) {
          final Offset pillPos = box.localToGlobal(Offset.zero);
          final Size pillSize = box.size;
          final Rect pillRect = pillPos & pillSize;
          if (!pillRect.contains(details.globalPosition)) {
            _dynamicIslandKey.currentState?.collapse();
          }
        }
      },
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        appBar: AppBar(title: const Text(''), flexibleSpace: const UserHeader()),
        body: Stack(
          children: [
            Column(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 16, top: 8, bottom: 4),
                  child: Align(alignment: Alignment.centerLeft, child: WeatherPillWidget()),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      IconButton(icon: const Icon(Icons.filter_list), onPressed: _showFilterOptions),
                      const SizedBox(width: 8),
                      const Text("Filter"),
                      const Spacer(),
                      Row(
                        children: [
                          const Text("Show Completed"),
                          Switch(
                            value: taskProvider.showCompletedTasks,
                            onChanged: (val) async {
                              taskProvider.toggleShowCompleted(val);
                              if (val) {
                                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompletedActivitiesScreen()));
                                taskProvider.toggleShowCompleted(false);
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Expanded(child: TaskOccurrencesView()),
              ],
            ),
            Positioned(bottom: 16, left: 20, child: DynamicIslandWidget(key: _dynamicIslandKey)),
          ],
        ),
        floatingActionButton: FloatingActionButton(onPressed: _showAddActivityModal, child: const Icon(Icons.add)),
      ),
    );
  }
}

/// UserHeader displays welcome text, date information and interactive profile settings.
class UserHeader extends StatelessWidget {
  const UserHeader({Key? key}) : super(key: key);

  void _showProfileSettings(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ProfileSettingSheet()));
  }

  void _showThemeSettings(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ThemeSettingsSheet()));
  }

  @override
  Widget build(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context);
    final userName = taskProvider.userName;
    String welcomeText = userName.isEmpty
        ? "Welcome"
        : (taskProvider.hasLaunchedBefore ? "Welcome back, $userName" : "Welcome, $userName");
    final String dateString = DateFormat('d MMM').format(DateTime.now());
    
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    final headerColor = themeNotifier.isDark ? darkThemeColors[themeNotifier.themeName]! : lightThemeColors[themeNotifier.themeName]!;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 50, 24, 4),
      decoration: BoxDecoration(color: headerColor, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(welcomeText, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
            const SizedBox(height: 4),
            Text(dateString, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70)),
          ])),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _showProfileSettings(context),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: CircleAvatar(backgroundColor: Colors.white, radius: 20, child: Text(taskProvider.profileIcon, style: const TextStyle(fontSize: 20))),
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(onTap: () => _showThemeSettings(context), child: const Icon(Icons.settings, color: Colors.white, size: 20)),
            ],
          )
        ],
      ),
    );
  }
}

/// TaskOccurrencesView displays active tasks on the home screen.
class TaskOccurrencesView extends StatelessWidget {
  const TaskOccurrencesView({Key? key}) : super(key: key);

  void _showSortOptions(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SortOptionsSheet()));
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TaskProvider>(context);
    List<TaskOccurrence> occurrences = provider.getUniqueTaskOccurrences().where((occ) => !occ.task.completed).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Activity List', style: Theme.of(context).textTheme.titleLarge),
            IconButton(icon: const Icon(Icons.sort), onPressed: () => _showSortOptions(context)),
          ]),
        ),
        Expanded(
          child: occurrences.isNotEmpty
              ? ListView.builder(
                  itemCount: occurrences.length,
                  itemBuilder: (context, index) {
                    TaskOccurrence occ = occurrences[index];
                    String emoji = Provider.of<TaskProvider>(context, listen: false).activityCategories[occ.task.category] ?? '';
                    Color priColor = occ.task.getPriorityColor(context);
                    return Dismissible(
                      key: ValueKey(occ.task.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        color: Colors.red,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) {
                        Provider.of<TaskProvider>(context, listen: false).deleteTask(occ.task);
                      },
                      child: Card(
                        elevation: 8,
                        shadowColor: Colors.black45,
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: Material(
                            elevation: 4,
                            shape: const CircleBorder(),
                            shadowColor: Colors.black38,
                            child: CircleAvatar(backgroundColor: Colors.white, child: Text(emoji)),
                          ),
                          title: Text(occ.task.text),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(DateFormat('yyyy-MM-dd').format(occ.occurrenceDate)),
                              if (occ.task.dueTime.isNotEmpty)
                                Text("Due: ${occ.task.dueTime}", style: const TextStyle(fontSize: 12)),
                              Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (occ.task.recurring != 'none')
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(shape: BoxShape.circle, color: priColor.withOpacity(0.2)),
                                      child: Icon(Icons.autorenew, size: 16, color: priColor),
                                    ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: priColor.withOpacity(0.2),
                                      border: Border.all(color: priColor, width: 1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(occ.task.getPriorityText(), style: TextStyle(color: priColor)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: IntrinsicWidth(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () {
                                    Navigator.of(context).push(MaterialPageRoute(builder: (context) => EditActivitySheet(task: occ.task)));
                                  },
                                ),
                                IconButton(
                                  icon: Icon(Icons.circle_outlined, size: 20, color: Theme.of(context).iconTheme.color),
                                  onPressed: () {
                                    Provider.of<TaskProvider>(context, listen: false).toggleTaskCompletion(occ.task);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                )
              : const Center(child: Text('')),
        ),
      ],
    );
  }
}

/// SortOptionsSheet allows sorting tasks.
class SortOptionsSheet extends StatefulWidget {
  const SortOptionsSheet({Key? key}) : super(key: key);
  @override
  _SortOptionsSheetState createState() => _SortOptionsSheetState();
}

class _SortOptionsSheetState extends State<SortOptionsSheet> {
  late String selectedOption;
  @override
  void initState() {
    super.initState();
    final provider = Provider.of<TaskProvider>(context, listen: false);
    selectedOption = provider.sortOption;
  }
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TaskProvider>(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Sort Options")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            RadioListTile<String>(
              title: const Text("All"),
              value: "all",
              groupValue: selectedOption,
              onChanged: (val) { setState(() { selectedOption = val!; }); },
            ),
            RadioListTile<String>(
              title: const Text("Recurring"),
              value: "recurring",
              groupValue: selectedOption,
              onChanged: (val) { setState(() { selectedOption = val!; }); },
            ),
            RadioListTile<String>(
              title: const Text("Non Recurring"),
              value: "non recurring",
              groupValue: selectedOption,
              onChanged: (val) { setState(() { selectedOption = val!; }); },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                provider.sortOption = selectedOption;
                provider.notifyListeners();
                Navigator.pop(context);
              },
              child: const Text("Apply"),
            ),
          ],
        ),
      ),
    );
  }
}

/// FilterOptionsSheet allows filtering tasks.
class FilterOptionsSheet extends StatefulWidget {
  const FilterOptionsSheet({Key? key}) : super(key: key);
  @override
  _FilterOptionsSheetState createState() => _FilterOptionsSheetState();
}

class _FilterOptionsSheetState extends State<FilterOptionsSheet> {
  late List<String> selectedFilters;
  @override
  void initState() {
    super.initState();
    selectedFilters = ['All'];
  }
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TaskProvider>(context);
    List<Widget> chips = [];
    chips.add(FilterChip(
      label: const Text("All"),
      selected: selectedFilters.contains("All"),
      onSelected: (selected) {
        setState(() {
          if (selected) {
            selectedFilters = ["All"];
          } else {
            selectedFilters.remove("All");
          }
        });
      },
    ));
    provider.activityCategories.forEach((activity, emoji) {
      bool isSelected = selectedFilters.contains(activity);
      chips.add(FilterChip(
        label: Text("$emoji $activity"),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            if (selected) {
              selectedFilters.remove("All");
              selectedFilters.add(activity);
            } else {
              selectedFilters.remove(activity);
              if (selectedFilters.isEmpty) {
                selectedFilters.add("All");
              }
            }
          });
        },
      ));
    });
    return Scaffold(
      appBar: AppBar(title: const Text("Filter Options")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Wrap(spacing: 8, children: chips),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                provider.filterCategories = selectedFilters;
                provider.notifyListeners();
                Navigator.pop(context);
              },
              child: const Text("Apply Filter"),
            ),
          ],
        ),
      ),
    );
  }
}

/// AddActivitySheet allows creating a new activity.
class AddActivitySheet extends StatefulWidget {
  const AddActivitySheet({Key? key}) : super(key: key);
  @override
  _AddActivitySheetState createState() => _AddActivitySheetState();
}

class _AddActivitySheetState extends State<AddActivitySheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  String _selectedCategory = 'Jogging';
  DateTime _selectedDate = DateTime.now();
  TimeOfDay? _selectedTime;
  final List<String> _participants = [];
  bool _notifyBefore = false;
  int _priority = 2;
  String _recurring = "none";
  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }
  Widget _buildActivityGrid() {
    final provider = Provider.of<TaskProvider>(context, listen: false);
    List<Widget> chips = [];
    provider.activityCategories.forEach((activity, emoji) {
      chips.add(
        GestureDetector(
          onTap: () { setState(() { _selectedCategory = activity; }); },
          child: Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _selectedCategory == activity ? Colors.deepPurple : Colors.transparent, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(height: 4),
                Text(activity, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    });
    return Wrap(children: chips);
  }
  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
    if (picked != null) {
      setState(() { _selectedDate = picked; });
    }
  }
  Future<void> _pickTime() async {
    TimeOfDay? picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) { setState(() { _selectedTime = picked; }); }
  }
  @override
  Widget build(BuildContext context) {
    String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    String timeStr = _selectedTime != null ? _selectedTime!.format(context) : '';
    return Scaffold(
      appBar: AppBar(title: const Text("Add New Activity")),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                validator: (value) { if (value == null || value.isEmpty) return 'Please enter a title'; return null; },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Text('Choose Activity', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _buildActivityGrid(),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
                value: _priority,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('High')),
                  DropdownMenuItem(value: 2, child: Text('Medium')),
                  DropdownMenuItem(value: 3, child: Text('Low')),
                ],
                onChanged: (val) { if (val != null) { setState(() { _priority = val; }); } },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Recurring', border: OutlineInputBorder()),
                value: _recurring,
                items: const [
                  DropdownMenuItem(value: "none", child: Text("None")),
                  DropdownMenuItem(value: "daily", child: Text("Daily")),
                  DropdownMenuItem(value: "monthly", child: Text("Monthly")),
                  DropdownMenuItem(value: "yearly", child: Text("Yearly")),
                ],
                onChanged: (val) { if (val != null) { setState(() { _recurring = val; }); } },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: _pickDate, child: Text('Date: $dateStr'))),
                  const SizedBox(width: 16),
                  Expanded(child: OutlinedButton(onPressed: _pickTime, child: Text(timeStr.isEmpty ? 'Select Time' : 'Time: $timeStr'))),
                ]
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text("Notify 10 mins before"),
                value: _notifyBefore,
                onChanged: (val) { setState(() { _notifyBefore = val; }); },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      final newTask = Task(
                        text: _titleController.text,
                        category: _selectedCategory,
                        notes: _notesController.text,
                        participants: _participants,
                        dueTime: timeStr,
                        dueDate: dateStr,
                        notifyBefore: _notifyBefore,
                        priority: _priority,
                        recurring: _recurring,
                      );
                      Provider.of<TaskProvider>(context, listen: false).addTask(newTask);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Add Activity'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// EditActivitySheet allows editing an existing activity.
class EditActivitySheet extends StatefulWidget {
  final Task task;
  const EditActivitySheet({Key? key, required this.task}) : super(key: key);
  @override
  _EditActivitySheetState createState() => _EditActivitySheetState();
}

class _EditActivitySheetState extends State<EditActivitySheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _notesController;
  late String _selectedCategory;
  late DateTime _selectedDate;
  TimeOfDay? _selectedTime;
  bool _notifyBefore = false;
  late int _priority;
  late String _recurring;
  
  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.text);
    _notesController = TextEditingController(text: widget.task.notes);
    _selectedCategory = widget.task.category;
    _selectedDate = DateFormat('yyyy-MM-dd').parse(widget.task.dueDate);
    _selectedTime = widget.task.dueTime.isNotEmpty ? TimeOfDay.fromDateTime(DateTime.tryParse("2000-01-01 ${widget.task.dueTime}") ?? DateTime.now()) : null;
    _notifyBefore = widget.task.notifyBefore;
    _priority = widget.task.priority;
    _recurring = widget.task.recurring;
  }
  
  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }
  
  Widget _buildActivityGrid() {
    final provider = Provider.of<TaskProvider>(context, listen: false);
    List<Widget> chips = [];
    provider.activityCategories.forEach((activity, emoji) {
      chips.add(
        GestureDetector(
          onTap: () { setState(() { _selectedCategory = activity; }); },
          child: Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _selectedCategory == activity ? Colors.deepPurple : Colors.transparent, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(Provider.of<TaskProvider>(context, listen: false).activityCategories[activity] ?? "", style: const TextStyle(fontSize: 28)),
                const SizedBox(height: 4),
                Text(activity, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    });
    return Wrap(children: chips);
  }
  
  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
    if (picked != null) { setState(() { _selectedDate = picked; }); }
  }
  
  Future<void> _pickTime() async {
    TimeOfDay? picked = await showTimePicker(context: context, initialTime: _selectedTime ?? TimeOfDay.now());
    if (picked != null) { setState(() { _selectedTime = picked; }); }
  }
  
  @override
  Widget build(BuildContext context) {
    String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    String timeStr = _selectedTime != null ? _selectedTime!.format(context) : '';
    return Scaffold(
      appBar: AppBar(title: const Text("Edit Activity")),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                validator: (value) { if (value == null || value.isEmpty) return 'Please enter a title'; return null; },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Text('Choose Activity', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _buildActivityGrid(),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
                value: _priority,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('High')),
                  DropdownMenuItem(value: 2, child: Text('Medium')),
                  DropdownMenuItem(value: 3, child: Text('Low')),
                ],
                onChanged: (val) { if (val != null) { setState(() { _priority = val; }); } },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Recurring', border: OutlineInputBorder()),
                value: _recurring,
                items: const [
                  DropdownMenuItem(value: "none", child: Text("None")),
                  DropdownMenuItem(value: "daily", child: Text("Daily")),
                  DropdownMenuItem(value: "monthly", child: Text("Monthly")),
                  DropdownMenuItem(value: "yearly", child: Text("Yearly")),
                ],
                onChanged: (val) { if (val != null) { setState(() { _recurring = val; }); } },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: _pickDate, child: Text('Date: $dateStr'))),
                  const SizedBox(width: 16),
                  Expanded(child: OutlinedButton(onPressed: _pickTime, child: Text(timeStr.isEmpty ? 'Select Time' : 'Time: $timeStr'))),
                ]
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text("Notify 10 mins before"),
                value: _notifyBefore,
                onChanged: (val) { setState(() { _notifyBefore = val; }); },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      final updatedTask = Task(
                        text: _titleController.text,
                        category: _selectedCategory,
                        notes: _notesController.text,
                        participants: widget.task.participants,
                        dueTime: timeStr,
                        dueDate: dateStr,
                        notifyBefore: _notifyBefore,
                        priority: _priority,
                        recurring: _recurring,
                      )..id = widget.task.id;
                      Provider.of<TaskProvider>(context, listen: false).updateTask(updatedTask);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Save Changes'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// FullCalendarModal displays a calendar with color dots for activities.
class FullCalendarModal extends StatefulWidget {
  const FullCalendarModal({Key? key}) : super(key: key);
  @override
  _FullCalendarModalState createState() => _FullCalendarModalState();
}

class _FullCalendarModalState extends State<FullCalendarModal> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  Future<void> _selectYear() async {
    DateTime? picked = await showDatePicker(context: context, initialDate: _focusedDay, firstDate: DateTime(2000), lastDate: DateTime(2100), initialEntryMode: DatePickerEntryMode.calendarOnly);
    if (picked != null) {
      setState(() { _focusedDay = DateTime(picked.year, _focusedDay.month, _focusedDay.day); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final headerTextColor = isDark ? Colors.white : Colors.black;
    final defaultTextColor = isDark ? Colors.white : Colors.black;
    final weekendTextColor = isDark ? Colors.white70 : Colors.black;
    return Scaffold(
      appBar: AppBar(title: const Text("Select a Date")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(onPressed: _selectYear, child: const Text('Select Year')),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 1,
              child: Consumer<TaskProvider>(
                builder: (context, taskProvider, child) {
                  List<TaskOccurrence> activeOccurrences = taskProvider.getUniqueTaskOccurrences().where((occ) => !occ.task.completed).toList();
                  return TableCalendar(
                    firstDay: DateTime.utc(2010, 10, 16),
                    lastDay: DateTime.utc(2030, 3, 14),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                      });
                    },
                    eventLoader: (day) {
                      return activeOccurrences.where((occurrence) => isSameDay(occurrence.occurrenceDate, day)).toList();
                    },
                    calendarBuilders: CalendarBuilders(
                      markerBuilder: (context, day, events) {
                        if (events.isEmpty) return const SizedBox();
                        final nonRecurring = events.where((e) {
                          final occ = e as TaskOccurrence;
                          return occ.task.recurring == 'none';
                        });
                        final recurring = events.where((e) {
                          final occ = e as TaskOccurrence;
                          return occ.task.recurring != 'none';
                        });
                        List<Widget> dots = [];
                        if (nonRecurring.isNotEmpty) {
                          dots.add(Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 1.0),
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red),
                          ));
                        }
                        if (recurring.isNotEmpty) {
                          dots.add(Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 1.0),
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.blue),
                          ));
                        }
                        return Row(mainAxisAlignment: MainAxisAlignment.center, children: dots);
                      },
                    ),
                    calendarStyle: CalendarStyle(
                      todayDecoration: BoxDecoration(color: Colors.deepPurple, shape: BoxShape.circle),
                      defaultTextStyle: TextStyle(color: defaultTextColor),
                      weekendTextStyle: TextStyle(color: weekendTextColor),
                    ),
                    headerStyle: HeaderStyle(formatButtonVisible: false, titleCentered: true, titleTextStyle: TextStyle(color: headerTextColor, fontSize: 16)),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Consumer<TaskProvider>(
                builder: (context, taskProvider, child) {
                  List<TaskOccurrence> eventsForSelectedDay = taskProvider.getUniqueTaskOccurrences().where((occurrence) => !occurrence.task.completed && isSameDay(occurrence.occurrenceDate, _selectedDay)).toList();
                  if (eventsForSelectedDay.isEmpty) {
                    return const Center(child: Text("No activities on this day", style: TextStyle(fontSize: 16)));
                  }
                  return Container(
                    width: double.infinity,
                    decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: eventsForSelectedDay.length,
                      itemBuilder: (context, index) {
                        TaskOccurrence occ = eventsForSelectedDay[index];
                        String timeLabel = occ.task.dueTime.isNotEmpty ? "Due: ${occ.task.dueTime}" : "";
                        Color dotColor = occ.task.recurring == 'none' ? Colors.red : Colors.blue;
                        return Card(
                          elevation: 8,
                          shadowColor: Colors.black45,
                          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor, boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(2, 2))]),
                            ),
                            title: Text(occ.task.text),
                            trailing: timeLabel.isNotEmpty ? Text(timeLabel) : null,
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () { Navigator.pop(context); }, child: const Text('Close Calendar')),
          ],
        ),
      ),
    );
  }
}

/// ProfileSettingSheet now only contains profile settings.
class ProfileSettingSheet extends StatefulWidget {
  const ProfileSettingSheet({Key? key}) : super(key: key);
  @override
  _ProfileSettingSheetState createState() => _ProfileSettingSheetState();
}

class _ProfileSettingSheetState extends State<ProfileSettingSheet> {
  late TextEditingController _nameController;
  String _selectedEmoji = '';
  final List<String> availableEmojis = ['👤', '😀', '😎', '🧐', '🤖', '👽', '🐶', '🍕', '🚂', '🚗'];
  @override
  void initState() {
    super.initState();
    final provider = Provider.of<TaskProvider>(context, listen: false);
    _selectedEmoji = provider.profileIcon;
    _nameController = TextEditingController(text: provider.userName);
  }
  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
  void _saveProfile() {
    final provider = Provider.of<TaskProvider>(context, listen: false);
    provider.setProfileIcon(_selectedEmoji);
    provider.setProfileName(_nameController.text.trim());
    Navigator.pop(context);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Profile Settings")),
      body: SingleChildScrollView(
        child: Padding(
          padding: MediaQuery.of(context).viewInsets.add(const EdgeInsets.symmetric(horizontal: 16, vertical: 24)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Your Name', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            Text('Select Profile Emoji', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: availableEmojis.map((emoji) {
                return GestureDetector(
                  onTap: () { setState(() { _selectedEmoji = emoji; }); },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _selectedEmoji == emoji ? Colors.amber : Colors.grey, width: 2)),
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saveProfile, child: const Text('Save Profile'))),
          ]),
        ),
      ),
    );
  }
}

/// ThemeSettingsSheet now includes the Location & Weather settings below Notifications.
class ThemeSettingsSheet extends StatefulWidget {
  const ThemeSettingsSheet({Key? key}) : super(key: key);
  @override
  _ThemeSettingsSheetState createState() => _ThemeSettingsSheetState();
}

class _ThemeSettingsSheetState extends State<ThemeSettingsSheet> {
  final TextEditingController _cityController = TextEditingController();
  // Updated suggestion list to include additional cities like Hyderabad, India.
  final List<String> cityOptions = [
    "Chicago, USA",
    "Chennai, India",
    "Chihuahua, Mexico",
    "Chengdu, China",
    "Chisinau, Moldova",
    "Hyderabad, India",
    "London, UK",
    "New York, USA",
    "Paris, France",
    "Tokyo, Japan"
  ];

  @override
  void initState() {
    super.initState();
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    _cityController.text = taskProvider.selectedCity;
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    final taskProvider = Provider.of<TaskProvider>(context);
    final modeLabel = themeNotifier.isDark ? "Switch to Light Mode" : "Switch to Dark Mode";

    return Scaffold(
      appBar: AppBar(title: const Text("Theme Settings")),
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        padding: MediaQuery.of(context).viewInsets.add(const EdgeInsets.symmetric(horizontal: 16, vertical: 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose Your Mode', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(modeLabel),
                Switch(value: themeNotifier.isDark, onChanged: (val) { themeNotifier.toggleTheme(val); }),
              ],
            ),
            const SizedBox(height: 24),
            Text('Themes', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: lightThemeColors.keys.map((themeKey) {
                return GestureDetector(
                  onTap: () { themeNotifier.updateTheme(themeKey); },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: themeNotifier.isDark ? darkThemeColors[themeKey] : lightThemeColors[themeKey],
                      border: Border.all(color: themeNotifier.themeName == themeKey ? Colors.white : Colors.transparent, width: 2),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Text('Notifications', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text("Enable Notifications for Upcoming Activities"),
              value: taskProvider.globalNotificationsEnabled,
              onChanged: (val) {
                taskProvider.globalNotificationsEnabled = val;
                taskProvider.saveData();
                taskProvider.notifyListeners();
              },
            ),
            const Divider(height: 32),
            // New Location & Weather Settings Section.
            Text("Location & Weather Settings", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.length < 3) {
                        return const Iterable<String>.empty();
                      }
                      return cityOptions.where((city) => city.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                    },
                    fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
                      // Use the controller we created so that text persists.
                      return TextField(
                        controller: _cityController,
                        focusNode: fieldFocusNode,
                        decoration: const InputDecoration(
                          labelText: "City (e.g., Chi...)",
                          border: OutlineInputBorder(),
                        ),
                      );
                    },
                    onSelected: (String selection) {
                      _cityController.text = selection;
                      taskProvider.updateSelectedCity(selection);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // Square box: tapping toggles the temperature unit.
                GestureDetector(
                  onTap: () {
                    taskProvider.toggleTempUnit();
                  },
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(color: Colors.blueGrey, border: Border.all(color: Colors.black), borderRadius: BorderRadius.circular(4)),
                    child: Center(
                      child: Text(taskProvider.tempUnit, style: const TextStyle(fontSize: 24, color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () { Navigator.pop(context); }, child: const Text('Save Theme Settings'))),
          ],
        ),
      ),
    );
  }
}