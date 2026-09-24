import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DBHelper.initDB();
  await ProductService.init();
  runApp(const MyApp());
}

// -------------------- MAIN APP --------------------
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart POS',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const HomeScreen(),
    );
  }
}

// -------------------- DATABASE --------------------
class DBHelper {
  static Database? _db;

  static Database get db {
    if (_db == null) throw Exception("DB not initialized");
    return _db!;
  }

  static Future<void> initDB() async {
    final path = p.join(await getDatabasesPath(), 'scancart.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE products(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT UNIQUE,
            name TEXT,
            price REAL
          )
        ''');

        await db.execute('''
          CREATE TABLE sales(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            total REAL
          )
        ''');

        await db.execute('''
          CREATE TABLE sale_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sale_id INTEGER,
            code TEXT,
            name TEXT,
            price REAL,
            quantity INTEGER,
            total REAL
          )
        ''');
      },
    );
  }

  static Future<void> addProduct(Map<String, dynamic> pdt) async {
    await db.insert('products', pdt,
        conflictAlgorithm: ConflictAlgorithm.abort);
  }

  static Future<List<Map<String, dynamic>>> getProducts() async {
    return db.query('products');
  }

  static Future<void> saveSale(List<Map<String, dynamic>> items, double total) async {
    final saleId = await db.insert('sales', {
      'timestamp': DateTime.now().toIso8601String(),
      'total': total,
    });

    for (var i in items) {
      await db.insert('sale_items', {
        'sale_id': saleId,
        ...i,
        'total': i['price'] * i['quantity'],
      });
    }
  }
}

// -------------------- PRODUCT --------------------
class Product {
  final int? id;
  final String code;
  final String name;
  final double price;

  Product({this.id, required this.code, required this.name, required this.price});

  Map<String, dynamic> toMap() => {
    'id': id,
    'code': code,
    'name': name,
    'price': price,
  };

  factory Product.fromMap(Map<String, dynamic> map) => Product(
    id: map['id'],
    code: map['code'],
    name: map['name'],
    price: (map['price'] as num).toDouble(),
  );
}

class ProductService {
  static ValueNotifier<Map<String, Product>> productMapNotifier = ValueNotifier({});

  static Future<void> init() async {
    final products = await DBHelper.getProducts();
    productMapNotifier.value = {
      for (var p in products) p['code']: Product.fromMap(p)
    };
  }

  static Future<void> addProduct(Product p) async {
    await DBHelper.addProduct(p.toMap());
    productMapNotifier.value = {
      ...productMapNotifier.value,
      p.code: p
    };
  }
}

// -------------------- CART --------------------
class CartItem {
  Product product;
  int quantity;

  CartItem({required this.product, this.quantity = 1});
}

class CartService {
  static ValueNotifier<List<CartItem>> cartNotifier = ValueNotifier([]);

  static void addItem(String code) {
    final products = ProductService.productMapNotifier.value;
    if (!products.containsKey(code)) return;

    final cart = List<CartItem>.from(cartNotifier.value);
    final index = cart.indexWhere((e) => e.product.code == code);

    if (index != -1) {
      cart[index].quantity++;
    } else {
      cart.add(CartItem(product: products[code]!));
    }

    cartNotifier.value = cart;
  }

  static double get total =>
      cartNotifier.value.fold(0, (sum, i) => sum + i.product.price * i.quantity);

  static void clearCart() => cartNotifier.value = [];
}

// -------------------- HOME --------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart POS'),
        centerTitle: true,
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              icon: const Icon(Icons.add,color: Colors.white,),
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const AddProductScreen()))),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: MobileScanner(
              onDetect: (capture) async {
                if (isProcessing) return;

                final code = capture.barcodes.first.rawValue;
                if (code == null) return;

                final products = ProductService.productMapNotifier.value;

                if (products.containsKey(code)) {
                  isProcessing = true;

                  CartService.addItem(code);

                  await Future.delayed(const Duration(milliseconds: 700));
                  isProcessing = false;
                }
              },
            ),
          ),

          // ✅ CART UI WITH COLUMN
          Expanded(
            flex: 3,
            child: ValueListenableBuilder(
              valueListenable: CartService.cartNotifier,
              builder: (_, List<CartItem> cart, __) {
                if (cart.isEmpty) {
                  return const Center(child: Text("Cart Empty"));
                }

                return ListView(
                  padding: const EdgeInsets.all(8),
                  children: cart.map((item) {
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            // Quantity control
                            Column(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.add, color: Colors.green),
                                  onPressed: () {
                                    final c = List<CartItem>.from(CartService.cartNotifier.value);
                                    final index = c.indexWhere((e) => e.product.code == item.product.code);
                                    if (index != -1) {
                                      c[index].quantity++;
                                      CartService.cartNotifier.value = c;
                                    }
                                  },
                                ),
                                Text("${item.quantity}", style: const TextStyle(fontSize: 16)),
                                IconButton(
                                  icon: const Icon(Icons.remove, color: Colors.red),
                                  onPressed: () {
                                    final c = List<CartItem>.from(CartService.cartNotifier.value);
                                    final index = c.indexWhere((e) => e.product.code == item.product.code);
                                    if (index != -1 && c[index].quantity > 1) {
                                      c[index].quantity--;
                                      CartService.cartNotifier.value = c;
                                    }
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(width: 16),

                            // Product details in column
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.product.name,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text("Price: Rs ${item.product.price}", style: const TextStyle(fontSize: 14)),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Net: Rs ${(item.product.price * item.quantity).toStringAsFixed(0)}",
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),

          const SizedBox(height: 10),

          ElevatedButton(
            onPressed: () => generatePDF(context),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade900,
                foregroundColor: Colors.white
            ),
            child: const Text("Checkout"),
          ),

          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // -------------------- PDF --------------------
  void generatePDF(BuildContext context) async {
    final cart = CartService.cartNotifier.value;
    if (cart.isEmpty) return;

    final pdf = pw.Document();

    final image = await imageFromAssetBundle('assets/images/cart.png'); // Add your logo

    pdf.addPage(
      pw.Page(
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  pw.Image(image, width: 60, height: 60),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text("CITY MART",
                            style: pw.TextStyle(
                                fontSize: 20,
                                fontWeight: pw.FontWeight.bold)),
                        pw.Text("Main Pabbi Bazar Karachi Market"),
                        pw.Text("Phone: +925473826838"),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                  child: pw.Text("Sale Invoice",
                      style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 10),
              pw.Text("Date: ${DateTime.now()}"),
              pw.SizedBox(height: 10),
              pw.Table.fromTextArray(
                headers: ['S.No', 'Product', 'Qty', 'Price', 'Net Amount'],
                data: List.generate(cart.length, (i) {
                  final e = cart[i];
                  return [
                    '${i + 1}',
                    e.product.name,
                    '${e.quantity}',
                    '${e.product.price}',
                    '${(e.product.price * e.quantity).toStringAsFixed(0)}'
                  ];
                }),
              ),
              pw.Divider(),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text("Total: Rs ${CartService.total}",
                    style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text("Thank you for visiting!")),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());

    await DBHelper.saveSale(
      cart.map((e) => {
        'code': e.product.code,
        'name': e.product.name,
        'price': e.product.price,
        'quantity': e.quantity
      }).toList(),
      CartService.total,
    );

    CartService.clearCart();

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Sale Completed")));
    }
  }
}

// -------------------- ADD PRODUCT --------------------
class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final code = TextEditingController();
  final name = TextEditingController();
  final price = TextEditingController();

  void save() async {
    try {
      await ProductService.addProduct(Product(
        code: code.text,
        name: name.text,
        price: double.parse(price.text),
      ));

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Duplicate Code")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Product"),
        centerTitle: true,
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextFormField(controller: code, decoration: const InputDecoration(labelText: "Code",border: OutlineInputBorder())),
            const SizedBox(height: 10,),
            TextFormField(controller: name, decoration: const InputDecoration(labelText: "Name",border: OutlineInputBorder())),
            const SizedBox(height: 10,),
            TextFormField(controller: price, decoration: const InputDecoration(labelText: "Price",border: OutlineInputBorder())),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: save,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade900,
                  foregroundColor: Colors.white
              ),
              child: const Text("Save"),)
          ],
        ),
      ),
    );
  }
}