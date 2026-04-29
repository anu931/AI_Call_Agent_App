import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/call_log_screen.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> requestPermissions() async {
  await [
    Permission.microphone,
    Permission.phone,
    Permission.storage
  ].request();
}

void main() async{
  WidgetsFlutterBinding.ensureInitialized();
  await requestPermissions();
  runApp(const MyApp());
} 

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context){
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const AppShell(),
    );
   }
  }
class AppShell extends StatefulWidget {
   const AppShell({super.key});

  @override
  State<AppShell> createState()=>_AppShellState();
}

 class _AppShellState extends State<AppShell>{
  int _page=0;

  final _pages=const[
    HomeScreen(),
    CallLogScreen(),
  ];
 
  @override
  Widget build(BuildContext context){
    return Scaffold(
    body: _pages[_page],
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: _page,
      onTap: (i) => setState(() => _page = i),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Call Log'),
       ],
     ),
   );
  }
} 
