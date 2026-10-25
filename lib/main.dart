import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppProvider(prefs),
      child: const TuccVendasApp(),
    ),
  );
}

// ==========================================
// UTILS / ADMIN AUTH HELPER
// ==========================================

class AdminAuth {
  static void verify(BuildContext context, VoidCallback onSuccess) {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🔒 Acesso Restrito (Administrador)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Esta ação exige a senha de Administrador:'),
              const SizedBox(height: 10),
              TextField(
                controller: passwordController,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Senha Admin'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (passwordController.text == provider.adminPassword) {
                Navigator.pop(context);
                onSuccess();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Senha incorreta!')));
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// MODELS
// ==========================================

class Product {
  final String id;
  final String name;
  final double costPrice;
  final double salePrice;
  int stockQuantity;
  final bool isService;
  final String? partnerId;

  Product({
    required this.id,
    required this.name,
    required this.costPrice,
    required this.salePrice,
    required this.stockQuantity,
    this.isService = false,
    this.partnerId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'costPrice': costPrice,
        'salePrice': salePrice,
        'stockQuantity': stockQuantity,
        'isService': isService,
        'partnerId': partnerId,
      };

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'],
        name: json['name'],
        costPrice: json['costPrice'],
        salePrice: json['salePrice'],
        stockQuantity: json['stockQuantity'],
        isService: json['isService'] ?? false,
        partnerId: json['partnerId'],
      );

  static double calculateSuggestedPrice(double cost, double marginPercent) {
    return cost * (1 + (marginPercent / 100));
  }
}

class Customer {
  final String id;
  final String name;
  final String phone;
  final bool isTuccCreditoEnabled;
  double pendingBalance;

  Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.isTuccCreditoEnabled = true,
    this.pendingBalance = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'isTuccCreditoEnabled': isTuccCreditoEnabled,
        'pendingBalance': pendingBalance,
      };

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id'],
        name: json['name'],
        phone: json['phone'],
        isTuccCreditoEnabled: json['isTuccCreditoEnabled'] ?? true,
        pendingBalance: json['pendingBalance'] ?? 0.0,
      );
}

class Partner {
  final String id;
  final String name;
  double balanceToRepay;

  Partner({
    required this.id,
    required this.name,
    this.balanceToRepay = 0.0,
  });

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'balanceToRepay': balanceToRepay};
  factory Partner.fromJson(Map<String, dynamic> json) => Partner(id: json['id'], name: json['name'], balanceToRepay: json['balanceToRepay'] ?? 0.0);
}

class Shift {
  final String operatorName;
  final DateTime startTime;
  double initialCash;
  double totalSuprimento;
  double totalSangria;

  Shift({
    required this.operatorName,
    required this.startTime,
    this.initialCash = 0.0,
    this.totalSuprimento = 0.0,
    this.totalSangria = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'operatorName': operatorName,
        'startTime': startTime.toIso8601String(),
        'initialCash': initialCash,
        'totalSuprimento': totalSuprimento,
        'totalSangria': totalSangria,
      };

  factory Shift.fromJson(Map<String, dynamic> json) => Shift(
        operatorName: json['operatorName'],
        startTime: DateTime.parse(json['startTime']),
        initialCash: json['initialCash'] ?? 0.0,
        totalSuprimento: json['totalSuprimento'] ?? 0.0,
        totalSangria: json['totalSangria'] ?? 0.0,
      );
}

enum PaymentMethod { dinheiro, cartao, pix, tuccCredito }

class SaleItem {
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double costPrice;
  final String? partnerId;

  SaleItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.costPrice,
    this.partnerId,
  });

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'costPrice': costPrice,
        'partnerId': partnerId,
      };

  factory SaleItem.fromJson(Map<String, dynamic> json) => SaleItem(
        productId: json['productId'],
        productName: json['productName'],
        quantity: json['quantity'],
        unitPrice: json['unitPrice'],
        costPrice: json['costPrice'],
        partnerId: json['partnerId'],
      );

  double get totalPrice => quantity * unitPrice;
  double get totalProfit => (unitPrice - costPrice) * quantity;
}

class Sale {
  final String id;
  final DateTime date;
  final List<SaleItem> items;
  final double totalAmount;
  final PaymentMethod paymentMethod;
  final String? customerId;
  final String operatorName;

  Sale({
    required this.id,
    required this.date,
    required this.items,
    required this.totalAmount,
    required this.paymentMethod,
    this.customerId,
    required this.operatorName,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'items': items.map((i) => i.toJson()).toList(),
        'totalAmount': totalAmount,
        'paymentMethod': paymentMethod.index,
        'customerId': customerId,
        'operatorName': operatorName,
      };

  factory Sale.fromJson(Map<String, dynamic> json) => Sale(
        id: json['id'],
        date: DateTime.parse(json['date']),
        items: (json['items'] as List).map((i) => SaleItem.fromJson(i)).toList(),
        totalAmount: json['totalAmount'],
        paymentMethod: PaymentMethod.values[json['paymentMethod']],
        customerId: json['customerId'],
        operatorName: json['operatorName'],
      );
}

// ==========================================
// PROVIDER (STATE MANAGEMENT + PERSISTENCE)
// ==========================================

class AppProvider with ChangeNotifier {
  final SharedPreferences _prefs;

  String appTitle = 'TUCC VENDAS';
  String appSubtitle = 'Templo de Umbanda Cigana Constanza';
  String reportPhone = '5511999999999';
  String adminPassword = '1234';

  List<Product> _products = [];
  List<Customer> _customers = [];
  List<Partner> _partners = [];
  List<Sale> _sales = [];
  Shift? _currentShift;

  AppProvider(this._prefs) {
    _loadData();
  }

  void _loadData() {
    adminPassword = _prefs.getString('adminPassword') ?? '1234';
    reportPhone = _prefs.getString('reportPhone') ?? '5511999999999';
    appTitle = _prefs.getString('appTitle') ?? 'TUCC VENDAS';
    appSubtitle = _prefs.getString('appSubtitle') ?? 'Templo de Umbanda Cigana Constanza';

    final productsStr = _prefs.getString('products');
    if (productsStr != null) {
      final List decoded = jsonDecode(productsStr);
      _products = decoded.map((e) => Product.fromJson(e)).toList();
    } else {
      _products = [
        Product(id: '1', name: 'Salgado Rissoles', costPrice: 3.0, salePrice: 6.0, stockQuantity: 20),
        Product(id: '2', name: 'Doce da Yasmim', costPrice: 4.0, salePrice: 8.0, stockQuantity: 15, partnerId: 'part_yasmim'),
        Product(id: '3', name: 'Serviço de Manutenção', costPrice: 0.0, salePrice: 50.0, stockQuantity: 999, isService: true),
      ];
    }

    final customersStr = _prefs.getString('customers');
    if (customersStr != null) {
      final List decoded = jsonDecode(customersStr);
      _customers = decoded.map((e) => Customer.fromJson(e)).toList();
    } else {
      _customers = [
        Customer(id: 'c1', name: 'Bru', phone: '5511995282760', isTuccCreditoEnabled: true),
        Customer(id: 'c2', name: 'Leida', phone: '5511940122955', isTuccCreditoEnabled: true),
        Customer(id: 'c3', name: 'Babi', phone: '5511940820842', isTuccCreditoEnabled: true),
        Customer(id: 'c4', name: 'Vinicius', phone: '5511947665145', isTuccCreditoEnabled: true),
        Customer(id: 'c5', name: 'Andréa', phone: '5511974644099', isTuccCreditoEnabled: true),
        Customer(id: 'c6', name: 'Alexandre', phone: '5511999990001', isTuccCreditoEnabled: true),
        Customer(id: 'c7', name: 'Malu Sousa', phone: '5511999990002', isTuccCreditoEnabled: true),
        Customer(id: 'c8', name: 'Samira', phone: '5511999990003', isTuccCreditoEnabled: true),
        Customer(id: 'c9', name: 'Sarah / Juca', phone: '5511999990004', isTuccCreditoEnabled: true),
        Customer(id: 'c10', name: 'Larissa Pescarolli', phone: '5511999990005', isTuccCreditoEnabled: true),
        Customer(id: 'c11', name: 'Cristiane Trindade TUCC', phone: '5511999990006', isTuccCreditoEnabled: true),
        Customer(id: 'c12', name: 'Sophia TUCC', phone: '5511999990007', isTuccCreditoEnabled: true),
        Customer(id: 'c13', name: 'Tchuca', phone: '5511999990008', isTuccCreditoEnabled: true),
        Customer(id: 'c14', name: 'Tia Sil Silva', phone: '5511999990009', isTuccCreditoEnabled: true),
        Customer(id: 'c15', name: 'Victória Toffolo', phone: '5511999990010', isTuccCreditoEnabled: true),
        Customer(id: 'c16', name: 'Vitoria TUCC', phone: '5511999990011', isTuccCreditoEnabled: true),
        Customer(id: 'c17', name: 'Yasmim', phone: '5511999990012', isTuccCreditoEnabled: true),
        Customer(id: 'c18', name: 'Murilo Miyazato', phone: '5511999990013', isTuccCreditoEnabled: true),
        Customer(id: 'c19', name: 'Gabriel Marques', phone: '5511999990014', isTuccCreditoEnabled: true),
        Customer(id: 'c20', name: 'Milena Teumo', phone: '5511999990015', isTuccCreditoEnabled: true),
        Customer(id: 'c21', name: 'Tainá Mattos', phone: '5511999990016', isTuccCreditoEnabled: true),
        Customer(id: 'c22', name: 'Renata Nascimento', phone: '5511999990017', isTuccCreditoEnabled: true),
        Customer(id: 'c23', name: 'Amanda', phone: '5511999990018', isTuccCreditoEnabled: true),
        Customer(id: 'c24', name: 'Aninha', phone: '5511999990019', isTuccCreditoEnabled: true),
        Customer(id: 'c25', name: 'Aline Souza', phone: '5511999990020', isTuccCreditoEnabled: true),
        Customer(id: 'c26', name: 'Daigo Terreiro', phone: '5511999990021', isTuccCreditoEnabled: true),
        Customer(id: 'c27', name: 'Juca', phone: '5511999990022', isTuccCreditoEnabled: true),
        Customer(id: 'c28', name: 'Keith', phone: '5511999990023', isTuccCreditoEnabled: true),
      ];
    }

    final partnersStr = _prefs.getString('partners');
    if (partnersStr != null) {
      final List decoded = jsonDecode(partnersStr);
      _partners = decoded.map((e) => Partner.fromJson(e)).toList();
    } else {
      _partners = [Partner(id: 'part_yasmim', name: 'Yasmim')];
    }

    final salesStr = _prefs.getString('sales');
    if (salesStr != null) {
      final List decoded = jsonDecode(salesStr);
      _sales = decoded.map((e) => Sale.fromJson(e)).toList();
    }

    final shiftStr = _prefs.getString('currentShift');
    if (shiftStr != null) {
      _currentShift = Shift.fromJson(jsonDecode(shiftStr));
    }
  }

  Future<void> _saveProducts() async {
    await _prefs.setString('products', jsonEncode(_products.map((e) => e.toJson()).toList()));
  }

  Future<void> _saveCustomers() async {
    await _prefs.setString('customers', jsonEncode(_customers.map((e) => e.toJson()).toList()));
  }

  Future<void> _savePartners() async {
    await _prefs.setString('partners', jsonEncode(_partners.map((e) => e.toJson()).toList()));
  }

  Future<void> _saveSales() async {
    await _prefs.setString('sales', jsonEncode(_sales.map((e) => e.toJson()).toList()));
  }

  Future<void> _saveShift() async {
    if (_currentShift == null) {
      await _prefs.remove('currentShift');
    } else {
      await _prefs.setString('currentShift', jsonEncode(_currentShift!.toJson()));
    }
  }

  void updateAppConfig(String newTitle, String newSubtitle, String newReportPhone, String newPassword) {
    appTitle = newTitle;
    appSubtitle = newSubtitle;
    reportPhone = newReportPhone;
    if (newPassword.isNotEmpty) {
      adminPassword = newPassword;
      _prefs.setString('adminPassword', adminPassword);
    }
    _prefs.setString('appTitle', appTitle);
    _prefs.setString('appSubtitle', appSubtitle);
    _prefs.setString('reportPhone', reportPhone);
    notifyListeners();
  }

  List<Product> get products => _products;
  List<Customer> get customers => _customers;
  List<Partner> get partners => _partners;
  List<Sale> get sales => _sales;
  Shift? get currentShift => _currentShift;

  void startShift(String operatorName, double initialCash) {
    _currentShift = Shift(
      operatorName: operatorName,
      startTime: DateTime.now(),
      initialCash: initialCash,
    );
    _saveShift();
    notifyListeners();
  }

  void closeShift() {
    _currentShift = null;
    _saveShift();
    notifyListeners();
  }

  void addSuprimento(double amount) {
    if (_currentShift != null) {
      _currentShift!.totalSuprimento += amount;
      _saveShift();
      notifyListeners();
    }
  }

  void addSangria(double amount) {
    if (_currentShift != null) {
      _currentShift!.totalSangria += amount;
      _saveShift();
      notifyListeners();
    }
  }

  void addProduct(Product product) {
    _products.add(product);
    _saveProducts();
    notifyListeners();
  }

  void updateProduct(Product updated) {
    final index = _products.indexWhere((p) => p.id == updated.id);
    if (index != -1) {
      _products[index] = updated;
      _saveProducts();
      notifyListeners();
    }
  }

  void updateStock(String productId, int newQuantity) {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index != -1) {
      _products[index].stockQuantity = newQuantity;
      _saveProducts();
      notifyListeners();
    }
  }

  void deleteProduct(String id) {
    _products.removeWhere((p) => p.id == id);
    _saveProducts();
    notifyListeners();
  }

  void addCustomer(Customer customer) {
    _customers.add(customer);
    _saveCustomers();
    notifyListeners();
  }

  void updateCustomer(Customer updated) {
    final index = _customers.indexWhere((c) => c.id == updated.id);
    if (index != -1) {
      _customers[index] = updated;
      _saveCustomers();
      notifyListeners();
    }
  }

  void deleteCustomer(String id) {
    _customers.removeWhere((c) => c.id == id);
    _saveCustomers();
    notifyListeners();
  }

  bool processSale({
    required List<SaleItem> items,
    required PaymentMethod paymentMethod,
    Customer? customer,
  }) {
    if (_currentShift == null) return false;

    double total = items.fold(0, (sum, item) => sum + item.totalPrice);

    if (paymentMethod == PaymentMethod.tuccCredito) {
      if (customer == null || !customer.isTuccCreditoEnabled) return false;
      customer.pendingBalance += total;
      _saveCustomers();
    }

    for (var item in items) {
      final product = _products.firstWhere((p) => p.id == item.productId);
      if (!product.isService) {
        product.stockQuantity -= item.quantity;
      }
      if (item.partnerId != null) {
        final partner = _partners.firstWhere((p) => p.id == item.partnerId);
        partner.balanceToRepay += item.totalPrice;
        _savePartners();
      }
    }
    _saveProducts();

    _sales.add(
      Sale(
        id: DateTime.now().toString(),
        date: DateTime.now(),
        items: items,
        totalAmount: total,
        paymentMethod: paymentMethod,
        customerId: customer?.id,
        operatorName: _currentShift!.operatorName,
      ),
    );
    _saveSales();

    notifyListeners();
    return true;
  }

  void payPendingBalance(Customer customer, double amountPaid) {
    customer.pendingBalance -= amountPaid;
    if (customer.pendingBalance < 0) customer.pendingBalance = 0;
    _saveCustomers();
    notifyListeners();
  }

  double getTotalSalesForDate(DateTime date) {
    return _sales
        .where((s) => s.date.year == date.year && s.date.month == date.month && s.date.day == date.day)
        .fold(0, (sum, s) => sum + s.totalAmount);
  }

  double getTotalProfitForDate(DateTime date) {
    double profit = 0;
    final daySales = _sales.where((s) => s.date.year == date.year && s.date.month == date.month && s.date.day == date.day);
    for (var sale in daySales) {
      for (var item in sale.items) {
        profit += item.totalProfit;
      }
    }
    return profit;
  }

  double get totalSalesToday => getTotalSalesForDate(DateTime.now());
  double get totalProfitToday => getTotalProfitForDate(DateTime.now());
}

// ==========================================
// SERVICES (WhatsApp & IA Gemini)
// ==========================================

class WhatsAppService {
  static Future<void> launchWhatsApp(String phone, String message) async {
    String cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final Uri url = Uri(
      scheme: 'https',
      host: 'wa.me',
      path: '/$cleanPhone',
      queryParameters: {'text': message},
    );

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        final fallbackUrl = Uri.parse('https://api.whatsapp.com/send?phone=$cleanPhone&text=${Uri.encodeComponent(message)}');
        await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir WhatsApp: $e');
    }
  }

  static Future<void> sendSaleReceipt({
    required String phone,
    required String customerName,
    required double totalAmount,
    required List<String> itemNames,
  }) async {
    String formattedDate = DateFormat('dd/MM/yyyy').format(DateTime.now());
    String message = "Olá $customerName! 🥪 *TUCC VENDAS*\n\n"
        "Data da compra: *$formattedDate*\n"
        "Sua compra no *TUCC CRÉDITO* foi realizada:\n"
        "${itemNames.map((e) => '- $e').join('\n')}\n\n"
        "*Total lançado:* R\$ ${totalAmount.toStringAsFixed(2)}\n\n"
        "Obrigado!";
    await launchWhatsApp(phone, message);
  }

  static Future<void> sendCustomerDebt({
    required String phone,
    required String customerName,
    required double pendingBalance,
  }) async {
    String formattedDate = DateFormat('dd/MM/yyyy').format(DateTime.now());
    String message = "Olá $customerName! 🥪 *TUCC VENDAS - TUCC CRÉDITO*\n\n"
        "Data do extrato: *$formattedDate*\n"
        "Passando para informar o seu saldo devedor atual:\n"
        "*Valor Pendente:* R\$ ${pendingBalance.toStringAsFixed(2)}\n\n"
        "Qualquer dúvida, estamos à disposição!";
    await launchWhatsApp(phone, message);
  }

  static Future<void> sendPaymentReceipt({
    required String phone,
    required String customerName,
    required double paidAmount,
    required double remainingBalance,
  }) async {
    String formattedDate = DateFormat('dd/MM/yyyy').format(DateTime.now());
    String message = "Olá $customerName! 🥪 *TUCC VENDAS - PAGAMENTO*\n\n"
        "Data do pagamento: *$formattedDate*\n"
        "Valor Pago: R\$ ${paidAmount.toStringAsFixed(2)}\n"
        "Saldo Restante Pendente: R\$ ${remainingBalance.toStringAsFixed(2)}\n\n"
        "Obrigado!";
    await launchWhatsApp(phone, message);
  }

  static Future<void> sendGeneralDebtReport({
    required String targetPhone,
    required List<Customer> customersWithDebt,
  }) async {
    double totalGeneral = customersWithDebt.fold(0, (sum, c) => sum + c.pendingBalance);
    String listText = customersWithDebt.map((c) => '• ${c.name}: R\$ ${c.pendingBalance.toStringAsFixed(2)}').join('\n');
    String message = "📊 *RELATÓRIO GERAL - TUCC CRÉDITO*\n\n$listText\n\n*TOTAL GERAL EM HAVER:* R\$ ${totalGeneral.toStringAsFixed(2)}";
    await launchWhatsApp(targetPhone, message);
  }

  static Future<void> sendDailyReport({
    required String targetPhone,
    required String reportText,
  }) async {
    await launchWhatsApp(targetPhone, reportText);
  }
}

class GeminiService {
  final String apiKey;
  late GenerativeModel _model;

  GeminiService(this.apiKey) {
    _model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
  }

  Future<String> analyzeBusinessAndSuggestFeatures(String salesContext) async {
    final prompt = '''
    Você é assistente de QA e consultor para o app 'TUCC VENDAS'.
    Analise o contexto: $salesContext
    Responda resumido:
    1. Desempenho e lucro.
    2. Sugestão funcional.
    3. Cenário de teste QA.
    ''';
    final response = await _model.generateContent([Content.text(prompt)]);
    return response.text ?? "Sem resposta.";
  }
}

// ==========================================
// APP ROOT & SCREENS
// ==========================================

class TuccVendasApp extends StatelessWidget {
  const TuccVendasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TUCC VENDAS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _showSettingsDialog(BuildContext context) {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final titleController = TextEditingController(text: provider.appTitle);
    final subtitleController = TextEditingController(text: provider.appSubtitle);
    final phoneController = TextEditingController(text: provider.reportPhone);
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configurações & Senha Admin'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Nome do Aplicativo')),
              TextField(controller: subtitleController, decoration: const InputDecoration(labelText: 'Subtítulo / Descrição')),
              TextField(controller: phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'WhatsApp p/ Relatórios')),
              TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Nova Senha Admin (Opcional)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              provider.updateAppConfig(
                titleController.text, 
                subtitleController.text, 
                phoneController.text,
                passwordController.text,
              );
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configurações salvas!')));
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    return WillPopScope(
      onWillPop: () async {
        bool allowed = false;
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('🔒 Modo Quiosque Ativo'),
            content: const SingleChildScrollView(
              child: Text('Para sair ou minimizar o aplicativo, é necessário a senha de administrador.'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ficar no App')),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  AdminAuth.verify(context, () {
                    SystemNavigator.pop();
                  });
                },
                child: const Text('Sair do App'),
              ),
            ],
          ),
        );
        return allowed;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/logo_cigana.png',
                height: 36,
                width: 36,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  provider.appTitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Configurações (Requer Admin)',
              onPressed: () => AdminAuth.verify(context, () => _showSettingsDialog(context)),
            ),
            IconButton(
              icon: const Icon(Icons.smart_toy),
              tooltip: 'Assistente IA & QA',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIAssistantScreen())),
            )
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(provider.appSubtitle, style: const TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Card(
                color: provider.currentShift == null ? Colors.red.shade100 : Colors.green.shade100,
                child: ListTile(
                  leading: Icon(provider.currentShift == null ? Icons.lock : Icons.badge),
                  title: Text(
                    provider.currentShift == null
                        ? "Caixa Fechado - Inicie o Turno"
                        : "Operador: ${provider.currentShift!.operatorName}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: ElevatedButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShiftScreen())),
                    child: Text(provider.currentShift == null ? "Abrir" : "Detalhes"),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: GridView.count(
                  crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  children: [
                    _buildMenuButton(
                      context,
                      title: "Nova Venda / PDV",
                      icon: Icons.point_of_sale,
                      color: Colors.green,
                      onTap: provider.currentShift == null
                          ? null
                          : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PosScreen())),
                    ),
                    _buildMenuButton(
                      context,
                      title: "Produtos & Estoque",
                      icon: Icons.fastfood,
                      color: Colors.orange,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductsScreen())),
                    ),
                    _buildMenuButton(
                      context,
                      title: "Auditoria de Inventário",
                      icon: Icons.inventory,
                      color: Colors.teal,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryScreen())),
                    ),
                    _buildMenuButton(
                      context,
                      title: "TUCC Crédito & Clientes",
                      icon: Icons.people,
                      color: Colors.blue,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomersScreen())),
                    ),
                    _buildMenuButton(
                      context,
                      title: "Relatórios & Terceiros",
                      icon: Icons.analytics,
                      color: Colors.purple,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen())),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton(BuildContext context, {required String title, required IconData icon, required Color color, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: onTap == null ? Colors.grey.shade300 : color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: onTap == null ? Colors.grey : color),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: onTap == null ? Colors.grey : color),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: onTap == null ? Colors.grey : Colors.black),
            ),
          ],
        ),
      ),
    );
  }
}

class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  final _operatorController = TextEditingController();
  final _cashController = TextEditingController(text: '0.0');

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Controle de Turno')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: provider.currentShift == null
            ? Column(
                children: [
                  TextField(controller: _operatorController, decoration: const InputDecoration(labelText: 'Nome do Operador do Dia')),
                  TextField(controller: _cashController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Fundo de Troco Inicial')),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      if (_operatorController.text.isNotEmpty) {
                        provider.startShift(_operatorController.text, double.parse(_cashController.text));
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('Abrir Turno'),
                  )
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Operador Ativo: ${provider.currentShift!.operatorName}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text("Troco Inicial: R\$ ${provider.currentShift!.initialCash.toStringAsFixed(2)}"),
                  Text("Suprimentos: R\$ ${provider.currentShift!.totalSuprimento.toStringAsFixed(2)}"),
                  Text("Sangrias: R\$ ${provider.currentShift!.totalSangria.toStringAsFixed(2)}"),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      provider.addSuprimento(10.0);
                      setState(() {});
                    },
                    child: const Text('Adicionar Suprimento (+R\$ 10)'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      provider.addSangria(10.0);
                      setState(() {});
                    },
                    child: const Text('Registrar Sangria (-R\$ 10)'),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(50)),
                    icon: const Icon(Icons.lock),
                    label: const Text('Encerrar Turno / Mudar Operador (Requer Admin)'),
                    onPressed: () {
                      AdminAuth.verify(context, () {
                        provider.closeShift();
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Turno encerrado com sucesso!')));
                      });
                    },
                  ),
                ],
              ),
      ),
    );
  }
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<AppProvider>(context, listen: false);
    for (var prod in provider.products) {
      _controllers[prod.id] = TextEditingController(text: prod.stockQuantity.toString());
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Auditoria de Inventário')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.teal.shade50,
            child: const Text(
              'Conte fisicamente os produtos e ajuste a quantidade abaixo. Se houver divergência, atualize para bater com o estoque real.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: provider.products.length,
              itemBuilder: (context, index) {
                final p = provider.products[index];
                if (p.isService) return const SizedBox.shrink();

                if (!_controllers.containsKey(p.id)) {
                  _controllers[p.id] = TextEditingController(text: p.stockQuantity.toString());
                }

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text('Sistema: ${p.stockQuantity} un', style: const TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _controllers[p.id],
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Contagem Real',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                          onPressed: () {
                            AdminAuth.verify(context, () {
                              int realQty = int.tryParse(_controllers[p.id]?.text ?? '') ?? p.stockQuantity;
                              provider.updateStock(p.id, realQty);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Estoque de ${p.name} atualizado para $realQty!')),
                              );
                            });
                          },
                          child: const Text('Salvar'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final List<SaleItem> _cart = [];
  PaymentMethod _selectedPayment = PaymentMethod.dinheiro;
  Customer? _selectedCustomer;
  String _customerSearchQuery = '';
  String _customerSortOrder = 'az';

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    double total = _cart.fold(0, (sum, i) => sum + i.totalPrice);

    List<Customer> filteredCustomers = provider.customers
        .where((c) => c.isTuccCreditoEnabled && c.name.toLowerCase().contains(_customerSearchQuery.toLowerCase()))
        .toList();

    if (_customerSortOrder == 'az') {
      filteredCustomers.sort((a, b) => a.name.compareTo(b.name));
    } else if (_customerSortOrder == 'za') {
      filteredCustomers.sort((a, b) => b.name.compareTo(a.name));
    } else if (_customerSortOrder == 'debito_desc') {
      filteredCustomers.sort((a, b) => b.pendingBalance.compareTo(a.pendingBalance));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Frente de Caixa (PDV)')),
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: ListView.builder(
              itemCount: provider.products.length,
              itemBuilder: (context, index) {
                final prod = provider.products[index];
                return ListTile(
                  title: Text(prod.name),
                  subtitle: Text("Estoque: ${prod.isService ? '∞' : prod.stockQuantity} | R\$ ${prod.salePrice.toStringAsFixed(2)}"),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_shopping_cart, color: Colors.green),
                    onPressed: () {
                      setState(() {
                        _cart.add(SaleItem(
                          productId: prod.id,
                          productName: prod.name,
                          quantity: 1,
                          unitPrice: prod.salePrice,
                          costPrice: prod.costPrice,
                          partnerId: prod.partnerId,
                        ));
                      });
                    },
                  ),
                );
              },
            ),
          ),
          const VerticalDivider(),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const Text("Carrinho", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    SizedBox(
                      height: 150,
                      child: ListView.builder(
                        itemCount: _cart.length,
                        itemBuilder: (context, index) => ListTile(
                          title: Text(_cart[index].productName),
                          subtitle: Text("R\$ ${_cart[index].unitPrice}"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => setState(() => _cart.removeAt(index)),
                          ),
                        ),
                      ),
                    ),
                    Text("Total: R\$ ${total.toStringAsFixed(2)}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
                    DropdownButton<PaymentMethod>(
                      value: _selectedPayment,
                      isExpanded: true,
                      items: PaymentMethod.values.map((m) {
                        return DropdownMenuItem(value: m, child: Text(m.name.toUpperCase()));
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedPayment = val!),
                    ),
                    if (_selectedPayment == PaymentMethod.tuccCredito) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(
                                hintText: 'Pesquisar cliente...',
                                prefixIcon: Icon(Icons.search),
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (val) => setState(() => _customerSearchQuery = val),
                            ),
                          ),
                          const SizedBox(width: 5),
                          DropdownButton<String>(
                            value: _customerSortOrder,
                            items: const [
                              DropdownMenuItem(value: 'az', child: Text('A-Z')),
                              DropdownMenuItem(value: 'za', child: Text('Z-A')),
                              DropdownMenuItem(value: 'debito_desc', child: Text('Maior Débito')),
                            ],
                            onChanged: (val) => setState(() => _customerSortOrder = val!),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      SizedBox(
                        height: 55,
                        child: DropdownButtonFormField<Customer>(
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            isDense: true,
                          ),
                          hint: const Text("Selecione o Cliente (TUCC CRÉDITO)"),
                          value: _selectedCustomer,
                          isExpanded: true,
                          items: filteredCustomers.map((c) {
                            return DropdownMenuItem(
                              value: c, 
                              child: Text("${c.name} (R\$ ${c.pendingBalance.toStringAsFixed(2)})", overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => _selectedCustomer = val),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size.fromHeight(50)),
                      onPressed: _cart.isEmpty
                          ? null
                          : () {
                              bool success = provider.processSale(
                                items: _cart,
                                paymentMethod: _selectedPayment,
                                customer: _selectedCustomer,
                              );

                              if (success) {
                                if (_selectedPayment == PaymentMethod.tuccCredito && _selectedCustomer != null) {
                                  WhatsAppService.sendSaleReceipt(
                                    phone: _selectedCustomer!.phone,
                                    customerName: _selectedCustomer!.name,
                                    totalAmount: total,
                                    itemNames: _cart.map((e) => e.productName).toList(),
                                  );
                                }
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venda Realizada!')));
                                setState(() => _cart.clear());
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro: Cliente sem TUCC CRÉDITO.')));
                              }
                            },
                      child: const Text("FINALIZAR", style: TextStyle(color: Colors.white)),
                    )
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});

  void _showProductDialog(BuildContext context, {Product? product}) {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final nameController = TextEditingController(text: product?.name ?? '');
    final costController = TextEditingController(text: product?.costPrice.toString() ?? '');
    final saleController = TextEditingController(text: product?.salePrice.toString() ?? '');
    final stockController = TextEditingController(text: product?.stockQuantity.toString() ?? '10');
    bool isService = product?.isService ?? false;
    String? partnerId = product?.partnerId;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) => AlertDialog(
          title: Text(product == null ? 'Novo Produto / Serviço (Admin)' : 'Editar Produto (Admin)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nome')),
                TextField(controller: costController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Preço de Custo')),
                TextField(controller: saleController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Preço de Venda')),
                if (!isService)
                  TextField(controller: stockController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantidade em Estoque')),
                SwitchListTile(
                  title: const Text('É Serviço?'),
                  value: isService,
                  onChanged: (val) => setStateModal(() => isService = val),
                ),
                DropdownButton<String?>(
                  hint: const Text('Parceiro Terceiro (Opcional)'),
                  value: partnerId,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Nenhum (Próprio)')),
                    ...provider.partners.map((pt) => DropdownMenuItem(value: pt.id, child: Text(pt.name))),
                  ],
                  onChanged: (val) => setStateModal(() => partnerId = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty) {
                  final newProd = Product(
                    id: product?.id ?? DateTime.now().toString(),
                    name: nameController.text,
                    costPrice: double.tryParse(costController.text) ?? 0.0,
                    salePrice: double.tryParse(saleController.text) ?? 0.0,
                    stockQuantity: int.tryParse(stockController.text) ?? 0,
                    isService: isService,
                    partnerId: partnerId,
                  );
                  if (product == null) {
                    provider.addProduct(newProd);
                  } else {
                    provider.updateProduct(newProd);
                  }
                  Navigator.pop(context);
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Produtos, Estoque & Margens')),
      body: ListView.builder(
        itemCount: provider.products.length,
        itemBuilder: (context, index) {
          final p = provider.products[index];
          double suggested = Product.calculateSuggestedPrice(p.costPrice, 40);
          return Card(
            child: ListTile(
              title: Text(p.name),
              subtitle: Text("Custo: R\$ ${p.costPrice} | Venda: R\$ ${p.salePrice} | Sugerido: R\$ ${suggested.toStringAsFixed(2)}"),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Est: ${p.isService ? 'Serviço' : p.stockQuantity}"),
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    tooltip: 'Editar (Requer Admin)',
                    onPressed: () => AdminAuth.verify(context, () => _showProductDialog(context, product: p)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Excluir (Requer Admin)',
                    onPressed: () => AdminAuth.verify(context, () => provider.deleteProduct(p.id)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Novo Produto (Requer Admin)',
        onPressed: () => AdminAuth.verify(context, () => _showProductDialog(context)),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _searchQuery = '';
  String _sortOrder = 'az';

  void _showCustomerDialog(BuildContext context, {Customer? customer}) {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final nameController = TextEditingController(text: customer?.name ?? '');
    final phoneController = TextEditingController(text: customer?.phone ?? '');
    bool isTuccCreditoEnabled = customer?.isTuccCreditoEnabled ?? true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) => AlertDialog(
          title: Text(customer == null ? 'Novo Cliente (Admin)' : 'Editar Cliente (Admin)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nome do Cliente')),
                TextField(controller: phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'WhatsApp / Telefone (ex: 55119...)')),
                SwitchListTile(
                  title: const Text('Permitir TUCC Crédito?'),
                  value: isTuccCreditoEnabled,
                  onChanged: (val) => setStateModal(() => isTuccCreditoEnabled = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty) {
                  final newCust = Customer(
                    id: customer?.id ?? DateTime.now().toString(),
                    name: nameController.text,
                    phone: phoneController.text,
                    isTuccCreditoEnabled: isTuccCreditoEnabled,
                    pendingBalance: customer?.pendingBalance ?? 0.0,
                  );
                  if (customer == null) {
                    provider.addCustomer(newCust);
                  } else {
                    provider.updateCustomer(newCust);
                  }
                  Navigator.pop(context);
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentDialog(BuildContext context, Customer customer) {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final amountController = TextEditingController(text: customer.pendingBalance.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Quitar / Pagar Débito - ${customer.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Débito Atual: R\$ ${customer.pendingBalance.toStringAsFixed(2)}'),
            const SizedBox(height: 10),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Valor Pago pelo Cliente', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              double paidAmount = double.tryParse(amountController.text.replaceAll(',', '.')) ?? 0.0;
              if (paidAmount > 0) {
                AdminAuth.verify(context, () {
                  provider.payPendingBalance(customer, paidAmount);
                  double remainingBalance = customer.pendingBalance;

                  WhatsAppService.sendPaymentReceipt(
                    phone: customer.phone,
                    customerName: customer.name,
                    paidAmount: paidAmount,
                    remainingBalance: remainingBalance,
                  );

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Pagamento de R\$ ${paidAmount.toStringAsFixed(2)} registrado!')),
                  );
                });
              }
            },
            child: const Text('Confirmar Pagamento'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    List<Customer> displayedCustomers = provider.customers
        .where((c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    if (_sortOrder == 'az') {
      displayedCustomers.sort((a, b) => a.name.compareTo(b.name));
    } else if (_sortOrder == 'za') {
      displayedCustomers.sort((a, b) => b.name.compareTo(a.name));
    } else if (_sortOrder == 'debito_desc') {
      displayedCustomers.sort((a, b) => b.pendingBalance.compareTo(a.pendingBalance));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Controle TUCC Crédito'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Enviar Relatório Geral de Débitos via WhatsApp (Caixa/Admin)',
            onPressed: () {
              final customersWithDebt = provider.customers.where((c) => c.pendingBalance > 0).toList();
              if (customersWithDebt.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum cliente com débito pendente.')));
              } else {
                WhatsAppService.sendGeneralDebtReport(
                  targetPhone: provider.reportPhone, 
                  customersWithDebt: customersWithDebt,
                );
              }
            },
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Pesquisar Cliente pelo Nome',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: _sortOrder,
                  items: const [
                    DropdownMenuItem(value: 'az', child: Text('A-Z')),
                    DropdownMenuItem(value: 'za', child: Text('Z-A')),
                    DropdownMenuItem(value: 'debito_desc', child: Text('Maior Débito')),
                  ],
                  onChanged: (val) => setState(() => _sortOrder = val!),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: displayedCustomers.length,
              itemBuilder: (context, index) {
                final c = displayedCustomers[index];
                return Card(
                  child: ListTile(
                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("Débito: R\$ ${c.pendingBalance.toStringAsFixed(2)} | Tel: ${c.phone}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chat, color: Colors.green),
                          tooltip: 'Enviar extrato por WhatsApp (Caixa/Admin)',
                          onPressed: () {
                            WhatsAppService.sendCustomerDebt(
                              phone: c.phone,
                              customerName: c.name,
                              pendingBalance: c.pendingBalance,
                            );
                          },
                        ),
                        if (c.pendingBalance > 0)
                          TextButton(
                            onPressed: () => _showPaymentDialog(context, c),
                            child: const Text("Pagar"),
                          ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          tooltip: 'Editar (Requer Admin)',
                          onPressed: () => AdminAuth.verify(context, () => _showCustomerDialog(context, customer: c)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: 'Excluir (Requer Admin)',
                          onPressed: () => AdminAuth.verify(context, () => provider.deleteCustomer(c.id)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Novo Cliente (Requer Admin)',
        onPressed: () => AdminAuth.verify(context, () => _showCustomerDialog(context)),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Relatórios & Terceiros')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: const Text('Vendas do Dia'),
              trailing: Text('R\$ ${provider.totalSalesToday.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Lucro Líquido Estimado'),
              trailing: Text('R\$ ${provider.totalProfitToday.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 18)),
            ),
          ),
          const Divider(),
          const Text("Repasse para Terceiros", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ...provider.partners.map((partner) => Card(
                child: ListTile(
                  title: Text("Parceiro: ${partner.name}"),
                  subtitle: Text("Repasse pendente: R\$ ${partner.balanceToRepay.toStringAsFixed(2)}"),
                  trailing: ElevatedButton(
                    onPressed: () => AdminAuth.verify(context, () {
                      provider.partners.firstWhere((p) => p.id == partner.id).balanceToRepay = 0;
                      provider.notifyListeners();
                    }),
                    child: const Text("Pagar Repasse"),
                  ),
                ),
              )),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.share),
            label: const Text("Enviar Relatório Diário com Estoque via WhatsApp"),
            onPressed: () {
              String stockList = provider.products
                  .map((p) => '• ${p.name}: ${p.isService ? "Serviço" : "${p.stockQuantity} un"}')
                  .join('\n');

              String report = "*RELATÓRIO DIÁRIO & ESTOQUE*\n\n"
                  "Total Vendido: R\$ ${provider.totalSalesToday.toStringAsFixed(2)}\n"
                  "Lucro Líquido: R\$ ${provider.totalProfitToday.toStringAsFixed(2)}\n"
                  "Operador: ${provider.currentShift?.operatorName ?? 'N/A'}\n\n"
                  "*ESTOQUE ATUAL:*\n$stockList";

              WhatsAppService.sendDailyReport(targetPhone: provider.reportPhone, reportText: report);
            },
          )
        ],
      ),
    );
  }
}

class AIAssistantScreen extends StatefulWidget {
  const AIAssistantScreen({super.key});

  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();
}

class _AIAssistantScreenState extends State<AIAssistantScreen> {
  String _aiResult = "Clique abaixo para gerar análise de QA, lucro e sugestões automáticas.";
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('IA Integrada & QA')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Text(_aiResult, style: const TextStyle(fontSize: 16)),
              ),
            ),
            if (_isLoading) const CircularProgressIndicator(),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.analytics),
              label: const Text("Executar Análise de IA & QA"),
              onPressed: () async {
                setState(() => _isLoading = true);
                final gemini = GeminiService("SUA_CHAVE_API_GEMINI_AQUI");
                String contextData = "Vendas Hoje: R\$ ${provider.totalSalesToday}, Lucro: R\$ ${provider.totalProfitToday}";
                String result = await gemini.analyzeBusinessAndSuggestFeatures(contextData);
                setState(() {
                  _aiResult = result;
                  _isLoading = false;
                });
              },
            )
          ],
        ),
      ),
    );
  }
}