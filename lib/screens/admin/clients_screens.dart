import 'package:flutter/material.dart';

import '../../models/client_record.dart';
import '../../services/client_service.dart';
import '../../utils/colors.dart';
import '../../widgets/admin_drawers.dart';
import '../../utils/app_text.dart';
import '../../services/google_places_service.dart';
import '../../models/address_suggestion.dart';

const Map<String, String> kCanadianProvinces = {
  'AB': 'Alberta',
  'BC': 'British Columbia',
  'MB': 'Manitoba',
  'NB': 'New Brunswick',
  'NL': 'Newfoundland and Labrador',
  'NS': 'Nova Scotia',
  'NT': 'Northwest Territories',
  'NU': 'Nunavut',
  'ON': 'Ontario',
  'PE': 'Prince Edward Island',
  'QC': 'Quebec',
  'SK': 'Saskatchewan',
  'YT': 'Yukon',
};

class AdminClientsPage extends StatefulWidget {
  const AdminClientsPage({super.key});

  @override
  State<AdminClientsPage> createState() => _AdminClientsPageState();
}

class _AdminClientsPageState extends State<AdminClientsPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ClientRecord> _filterClients(List<ClientRecord> clients) {
    final query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) {
      return clients;
    }

    return clients.where((client) {
      final contactMatches = client.contacts.any(
            (contact) =>
        contact.name.toLowerCase().contains(query) ||
            contact.phone.toLowerCase().contains(query) ||
            contact.email.toLowerCase().contains(query),
      );

      return client.businessName.toLowerCase().contains(query) ||
          client.name.toLowerCase().contains(query) ||
          client.phone.toLowerCase().contains(query) ||
          client.email.toLowerCase().contains(query) ||
          client.address.toLowerCase().contains(query) ||
          contactMatches;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      endDrawer: AdminMenuDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateClientPage(),
            ),
          );
        },
        backgroundColor: kPurple,
        shape: CircleBorder(),
        child: Icon(Icons.add, color: Colors.white, size: 30),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            children: [
              SizedBox(height: 10),
              Row(
                children: [
                  Spacer(),
                  Text(
                    tr(context, 'Edit Clients'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Spacer(),
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: () => Scaffold.of(context).openEndDrawer(),
                      child: Icon(Icons.menu, size: 28),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: tr(
                    context,
                    'Search by business name, name or phone number...',
                  ),
                  hintStyle: TextStyle(color: Color(0xFF9A9A9A)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: kPurple),
                  ),
                ),
              ),
              SizedBox(height: 12),
              Expanded(
                child: StreamBuilder<List<ClientRecord>>(
                  stream: ClientService.clientsStream(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(tr(context, 'Something went wrong')),
                      );
                    }

                    if (!snapshot.hasData) {
                      return Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    final clients = _filterClients(snapshot.data!);

                    if (clients.isEmpty) {
                      return Center(
                        child: Text(tr(context, 'No clients found')),
                      );
                    }

                    return ListView.separated(
                      itemCount: clients.length,
                      separatorBuilder: (_, _) => SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final client = clients[index];
                        return _ClientCard(
                          client: client,
                          onTap: () async {
                            await showClientDetailsPopup(context, client: client);
                          },
                          onEdit: () async {
                            await showEditClientPopup(context, client: client);
                          },
                          onDelete: () async {
                            await ClientService.deleteClient(client.id);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- CLIENTS DARK ---------------- */

class AdminClientsDarkPage extends StatefulWidget {
  const AdminClientsDarkPage({super.key});

  @override
  State<AdminClientsDarkPage> createState() => _AdminClientsDarkPageState();
}

class _AdminClientsDarkPageState extends State<AdminClientsDarkPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ClientRecord> _filterClients(List<ClientRecord> clients) {
    final query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) {
      return clients;
    }

    return clients.where((client) {
      final contactMatches = client.contacts.any(
            (contact) =>
        contact.name.toLowerCase().contains(query) ||
            contact.phone.toLowerCase().contains(query) ||
            contact.email.toLowerCase().contains(query),
      );

      return client.businessName.toLowerCase().contains(query) ||
          client.name.toLowerCase().contains(query) ||
          client.phone.toLowerCase().contains(query) ||
          client.email.toLowerCase().contains(query) ||
          client.address.toLowerCase().contains(query) ||
          contactMatches;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      endDrawer: AdminMenuDrawerDark(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateClientDarkPage(),
            ),
          );
        },
        backgroundColor: kPurple,
        shape: CircleBorder(),
        child: Icon(Icons.add, color: Colors.white, size: 30),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            children: [
              SizedBox(height: 10),
              Row(
                children: [
                  Spacer(),
                  Text(
                    tr(context, 'Edit Clients'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  Spacer(),
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: () => Scaffold.of(context).openEndDrawer(),
                      child: Icon(Icons.menu, size: 28, color: Colors.white),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14),
              TextField(
                controller: _searchController,
                style: TextStyle(color: Colors.white),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: tr(
                    context,
                    'Search by business name, name or phone number...',
                  ),
                  hintStyle: TextStyle(color: Color(0xFF9A9A9A)),
                  filled: true,
                  fillColor: Color(0xFF171717),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Color(0xFF2D2D2D)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: kPurple),
                  ),
                ),
              ),
              SizedBox(height: 12),
              Expanded(
                child: StreamBuilder<List<ClientRecord>>(
                  stream: ClientService.clientsStream(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          tr(context, 'Something went wrong'),
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    }

                    if (!snapshot.hasData) {
                      return Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    final clients = _filterClients(snapshot.data!);

                    if (clients.isEmpty) {
                      return Center(
                        child: Text(
                          tr(context, 'No clients found'),
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: clients.length,
                      separatorBuilder: (_, _) => SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final client = clients[index];
                        return _ClientCardDark(
                          client: client,
                          onTap: () async {
                            await showClientDetailsDarkPopup(context, client: client);
                          },
                          onEdit: () async {
                            await showEditClientDarkPopup(context, client: client);
                          },
                          onDelete: () async {
                            await ClientService.deleteClient(client.id);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessContactFormData {
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController emailController;

  _BusinessContactFormData({
    String name = '',
    String phone = '',
    String email = '',
  })  : nameController = TextEditingController(text: name),
        phoneController = TextEditingController(text: phone),
        emailController = TextEditingController(text: email);

  ClientContact toClientContact() {
    return ClientContact(
      name: nameController.text.trim(),
      phone: phoneController.text.trim(),
      email: emailController.text.trim(),
    );
  }

  bool get isCompletelyEmpty =>
      nameController.text.trim().isEmpty &&
          phoneController.text.trim().isEmpty &&
          emailController.text.trim().isEmpty;

  bool get isValid =>
      nameController.text.trim().isNotEmpty &&
          (phoneController.text.trim().isNotEmpty ||
              emailController.text.trim().isNotEmpty);

  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
  }
}

/* ---------------- CREATE CLIENT LIGHT ---------------- */

class CreateClientPage extends StatefulWidget {
  const CreateClientPage({super.key});

  @override
  State<CreateClientPage> createState() => _CreateClientPageState();
}

class _CreateClientPageState extends State<CreateClientPage> {
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressSearchController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  String _selectedProvince = 'QC';
  final TextEditingController _postalCodeController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final List<_BusinessContactFormData> _contacts = [];

  bool _isSaving = false;
  String? _pageError;

  List<AddressSuggestion> _addressSuggestions = [];
  bool _showAddressSuggestions = false;
  bool _isLoadingAddressSuggestions = false;

  bool get _isBusinessClient => _businessNameController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _nameController.dispose();
    _addressSearchController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    for (final contact in _contacts) {
      contact.dispose();
    }
    super.dispose();
  }

  Future<void> _searchAddresses(String value) async {
    if (value.trim().isEmpty) {
      setState(() {
        _addressSuggestions = [];
        _showAddressSuggestions = false;
        _isLoadingAddressSuggestions = false;
      });
      return;
    }

    setState(() {
      _showAddressSuggestions = true;
      _isLoadingAddressSuggestions = true;
    });

    try {
      final results = await GooglePlacesService.autocomplete(value);

      if (!mounted) return;

      setState(() {
        _addressSuggestions = results;
        _isLoadingAddressSuggestions = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _addressSuggestions = [];
        _isLoadingAddressSuggestions = false;
        _showAddressSuggestions = true;
      });
    }
  }

  Future<void> _selectAddress(AddressSuggestion suggestion) async {
    final details = await GooglePlacesService.getPlaceDetails(suggestion.placeId);

    if (!mounted) return;

    setState(() {
      _addressSearchController.text = details.fullAddress;
      _streetController.text = details.street;
      _cityController.text = details.city;
      _selectedProvince = details.province.isNotEmpty &&
          kCanadianProvinces.containsKey(details.province)
          ? details.province
          : 'QC';
      _postalCodeController.text = details.postalCode;
      _showAddressSuggestions = false;
    });
  }

  void _clearError() {
    if (_pageError != null) {
      setState(() {
        _pageError = null;
      });
    }
  }

  void _handleBusinessNameChanged(String value) {
    _clearError();

    if (value.trim().isEmpty && _contacts.isNotEmpty) {
      for (final contact in _contacts) {
        contact.dispose();
      }
      _contacts.clear();
    }

    setState(() {});
  }

  void _addContact() {
    setState(() {
      _contacts.add(_BusinessContactFormData());
    });
  }

  void _removeContact(int index) {
    final removed = _contacts.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Future<void> _saveClient() async {
    if (_isSaving) return;

    final businessName = _businessNameController.text.trim();
    final name = _nameController.text.trim();
    final street = _streetController.text.trim();
    final city = _cityController.text.trim();
    final province = _selectedProvince.trim();
    final postalCode = _postalCodeController.text.trim();

    final address = [street, city, province, postalCode]
        .where((e) => e.isNotEmpty)
        .join(', ');

    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    final addressRequired = businessName.isEmpty;

    if (businessName.isEmpty && name.isEmpty) {
      setState(() {
        _pageError = tr(
          context,
          'Business name or name is required',
        );
      });
      return;
    }

    if (phone.isEmpty && email.isEmpty) {
      setState(() {
        _pageError = tr(
          context,
          'Either phone number or email is required',
        );
      });
      return;
    }

    if (addressRequired &&
        (street.isEmpty ||
            city.isEmpty ||
            province.isEmpty ||
            postalCode.isEmpty)) {
      setState(() {
        _pageError = tr(
          context,
          'Address is required when no business name is entered',
        );
      });
      return;
    }

    final cleanedContacts = _contacts
        .where((c) => !c.isCompletelyEmpty)
        .map((c) => c.toClientContact())
        .toList();

    final hasInvalidContact = _contacts.any(
          (c) => !c.isCompletelyEmpty && !c.isValid,
    );

    if (hasInvalidContact) {
      setState(() {
        _pageError = tr(
          context,
          'Each contact must have a name and a phone number or email',
        );
      });
      return;
    }

    setState(() {
      _pageError = null;
      _isSaving = true;
    });

    try {
      await ClientService.addClient(
        businessName: businessName,
        name: name,
        address: address,
        phone: phone,
        email: email,
        contacts: cleanedContacts,
      );

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pageError = '${tr(context, 'Error')}: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  Expanded(
                    child: Text(
                      tr(context, 'Add Client'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(width: 48),
                ],
              ),
              SizedBox(height: 18),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Color(0xFFE0E0E0)),
                ),
                child: Column(
                  children: [
                    _clientFormField(
                      context: context,
                      controller: _businessNameController,
                      hintText: 'Business name',
                      onChanged: _handleBusinessNameChanged,
                    ),
                    SizedBox(height: 12),
                    _clientFormField(
                      context: context,
                      controller: _nameController,
                      hintText: 'Name',
                      onChanged: (_) => _clearError(),
                    ),
                    SizedBox(height: 12),
                    _clientFormField(
                      context: context,
                      controller: _addressSearchController,
                      hintText: 'Search address',
                      onChanged: (value) {
                        _clearError();
                        _searchAddresses(value);
                      },
                    ),
                    if (_showAddressSuggestions)
                      Container(
                        margin: EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Color(0xFFE0E0E0)),
                        ),
                        constraints: BoxConstraints(maxHeight: 220),
                        child: _isLoadingAddressSuggestions
                            ? Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        )
                            : _addressSuggestions.isEmpty
                            ? Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            tr(context, 'No address found'),
                            style: TextStyle(
                              color: Colors.black54,
                            ),
                          ),
                        )
                            : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _addressSuggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion =
                            _addressSuggestions[index];
                            return ListTile(
                              title: Text(suggestion.description),
                              onTap: () => _selectAddress(suggestion),
                            );
                          },
                        ),
                      ),
                    SizedBox(height: 12),
                    _clientFormField(
                      context: context,
                      controller: _streetController,
                      hintText: 'Street',
                    ),
                    SizedBox(height: 12),
                    _clientFormField(
                      context: context,
                      controller: _cityController,
                      hintText: 'City',
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _clientFormField(
                            context: context,
                            controller: _postalCodeController,
                            hintText: 'Postal code',
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: _provinceDropdownField(
                            context: context,
                            value: _selectedProvince,
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _selectedProvince = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    _clientFormField(
                      context: context,
                      controller: _phoneController,
                      hintText: 'Phone number',
                      onChanged: (_) => _clearError(),
                    ),
                    SizedBox(height: 12),
                    _clientFormField(
                      context: context,
                      controller: _emailController,
                      hintText: 'Email',
                      onChanged: (_) => _clearError(),
                    ),
                    if (_isBusinessClient) ...[
                      SizedBox(height: 18),
                      _contactsSectionLight(
                        context: context,
                        contacts: _contacts,
                        onAddContact: _addContact,
                        onRemoveContact: _removeContact,
                        onChanged: _clearError,
                      ),
                    ],
                    if (_pageError != null) ...[
                      SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Color(0xFFFFEAEA),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Color(0xFFFFB3B3)),
                        ),
                        child: Text(
                          _pageError!,
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveClient,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _isSaving
                            ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                            : Text(tr(context, 'Add Client')),
                      ),
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
}

/* ---------------- CREATE CLIENT DARK ---------------- */

class CreateClientDarkPage extends StatefulWidget {
  const CreateClientDarkPage({super.key});

  @override
  State<CreateClientDarkPage> createState() => _CreateClientDarkPageState();
}

class _CreateClientDarkPageState extends State<CreateClientDarkPage> {
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressSearchController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  String _selectedProvince = 'QC';
  final TextEditingController _postalCodeController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final List<_BusinessContactFormData> _contacts = [];

  bool _isSaving = false;
  String? _pageError;

  List<AddressSuggestion> _addressSuggestions = [];
  bool _showAddressSuggestions = false;
  bool _isLoadingAddressSuggestions = false;

  bool get _isBusinessClient => _businessNameController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _nameController.dispose();
    _addressSearchController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    for (final contact in _contacts) {
      contact.dispose();
    }
    super.dispose();
  }

  Future<void> _searchAddresses(String value) async {
    if (value.trim().isEmpty) {
      setState(() {
        _addressSuggestions = [];
        _showAddressSuggestions = false;
        _isLoadingAddressSuggestions = false;
      });
      return;
    }

    setState(() {
      _showAddressSuggestions = true;
      _isLoadingAddressSuggestions = true;
    });

    try {
      final results = await GooglePlacesService.autocomplete(value);

      if (!mounted) return;

      setState(() {
        _addressSuggestions = results;
        _isLoadingAddressSuggestions = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _addressSuggestions = [];
        _isLoadingAddressSuggestions = false;
        _showAddressSuggestions = true;
      });
    }
  }

  Future<void> _selectAddress(AddressSuggestion suggestion) async {
    final details = await GooglePlacesService.getPlaceDetails(suggestion.placeId);

    if (!mounted) return;

    setState(() {
      _addressSearchController.text = details.fullAddress;
      _streetController.text = details.street;
      _cityController.text = details.city;
      _selectedProvince = details.province.isNotEmpty &&
          kCanadianProvinces.containsKey(details.province)
          ? details.province
          : 'QC';
      _postalCodeController.text = details.postalCode;
      _showAddressSuggestions = false;
    });
  }

  void _clearError() {
    if (_pageError != null) {
      setState(() {
        _pageError = null;
      });
    }
  }

  void _handleBusinessNameChanged(String value) {
    _clearError();

    if (value.trim().isEmpty && _contacts.isNotEmpty) {
      for (final contact in _contacts) {
        contact.dispose();
      }
      _contacts.clear();
    }

    setState(() {});
  }

  void _addContact() {
    setState(() {
      _contacts.add(_BusinessContactFormData());
    });
  }

  void _removeContact(int index) {
    final removed = _contacts.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Future<void> _saveClient() async {
    if (_isSaving) return;

    final businessName = _businessNameController.text.trim();
    final name = _nameController.text.trim();
    final street = _streetController.text.trim();
    final city = _cityController.text.trim();
    final province = _selectedProvince.trim();
    final postalCode = _postalCodeController.text.trim();

    final address = [street, city, province, postalCode]
        .where((e) => e.isNotEmpty)
        .join(', ');

    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    final addressRequired = businessName.isEmpty;

    if (businessName.isEmpty && name.isEmpty) {
      setState(() {
        _pageError = tr(
          context,
          'Business name or name is required',
        );
      });
      return;
    }

    if (phone.isEmpty && email.isEmpty) {
      setState(() {
        _pageError = tr(
          context,
          'Either phone number or email is required',
        );
      });
      return;
    }

    if (addressRequired &&
        (street.isEmpty ||
            city.isEmpty ||
            province.isEmpty ||
            postalCode.isEmpty)) {
      setState(() {
        _pageError = tr(
          context,
          'Address is required when no business name is entered',
        );
      });
      return;
    }

    final cleanedContacts = _contacts
        .where((c) => !c.isCompletelyEmpty)
        .map((c) => c.toClientContact())
        .toList();

    final hasInvalidContact = _contacts.any(
          (c) => !c.isCompletelyEmpty && !c.isValid,
    );

    if (hasInvalidContact) {
      setState(() {
        _pageError = tr(
          context,
          'Each contact must have a name and a phone number or email',
        );
      });
      return;
    }

    setState(() {
      _pageError = null;
      _isSaving = true;
    });

    try {
      await ClientService.addClient(
        businessName: businessName,
        name: name,
        address: address,
        phone: phone,
        email: email,
        contacts: cleanedContacts,
      );

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pageError = '${tr(context, 'Error')}: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      tr(context, 'Add Client'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(width: 48),
                ],
              ),
              SizedBox(height: 18),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Color(0xFF111111),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Color(0xFF2A2A2A)),
                ),
                child: Column(
                  children: [
                    _clientFormFieldDark(
                      context: context,
                      controller: _businessNameController,
                      hintText: 'Business name',
                      onChanged: _handleBusinessNameChanged,
                    ),
                    SizedBox(height: 12),
                    _clientFormFieldDark(
                      context: context,
                      controller: _nameController,
                      hintText: 'Name',
                      onChanged: (_) => _clearError(),
                    ),
                    SizedBox(height: 12),
                    _clientFormFieldDark(
                      context: context,
                      controller: _addressSearchController,
                      hintText: 'Search address',
                      onChanged: (value) {
                        _clearError();
                        _searchAddresses(value);
                      },
                    ),
                    if (_showAddressSuggestions)
                      Container(
                        margin: EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: Color(0xFF171717),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Color(0xFF2D2D2D)),
                        ),
                        constraints: BoxConstraints(maxHeight: 220),
                        child: _isLoadingAddressSuggestions
                            ? Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        )
                            : _addressSuggestions.isEmpty
                            ? Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            tr(context, 'No address found'),
                            style: TextStyle(
                              color: Colors.white70,
                            ),
                          ),
                        )
                            : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _addressSuggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion =
                            _addressSuggestions[index];
                            return ListTile(
                              title: Text(
                                suggestion.description,
                                style: TextStyle(
                                  color: Colors.white,
                                ),
                              ),
                              onTap: () => _selectAddress(suggestion),
                            );
                          },
                        ),
                      ),
                    SizedBox(height: 12),
                    _clientFormFieldDark(
                      context: context,
                      controller: _streetController,
                      hintText: 'Street',
                    ),
                    SizedBox(height: 12),
                    _clientFormFieldDark(
                      context: context,
                      controller: _cityController,
                      hintText: 'City',
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _clientFormFieldDark(
                            context: context,
                            controller: _postalCodeController,
                            hintText: 'Postal code',
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: _provinceDropdownFieldDark(
                            context: context,
                            value: _selectedProvince,
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _selectedProvince = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    _clientFormFieldDark(
                      context: context,
                      controller: _phoneController,
                      hintText: 'Phone number',
                      onChanged: (_) => _clearError(),
                    ),
                    SizedBox(height: 12),
                    _clientFormFieldDark(
                      context: context,
                      controller: _emailController,
                      hintText: 'Email',
                      onChanged: (_) => _clearError(),
                    ),
                    if (_isBusinessClient) ...[
                      SizedBox(height: 18),
                      _contactsSectionDark(
                        context: context,
                        contacts: _contacts,
                        onAddContact: _addContact,
                        onRemoveContact: _removeContact,
                        onChanged: _clearError,
                      ),
                    ],
                    if (_pageError != null) ...[
                      SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Color(0xFF2A1212),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Color(0xFF5A2A2A)),
                        ),
                        child: Text(
                          _pageError!,
                          style: TextStyle(
                            color: Color(0xFFFF8A8A),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveClient,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _isSaving
                            ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                            : Text(tr(context, 'Add Client')),
                      ),
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
}

Widget _provinceDropdownField({
  required BuildContext context,
  required String value,
  required ValueChanged<String?> onChanged,
}) {
  return DropdownButtonFormField<String>(
    value: value,
    isExpanded: true,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: tr(context, 'Province'),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    items: kCanadianProvinces.entries.map((entry) {
      return DropdownMenuItem(
        value: entry.key,
        child: Text(
          '${entry.value} (${entry.key})',
          style: TextStyle(fontSize: 13),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      );
    }).toList(),
  );
}

Widget _provinceDropdownFieldDark({
  required BuildContext context,
  required String value,
  required ValueChanged<String?> onChanged,
}) {
  return DropdownButtonFormField<String>(
    value: value,
    isExpanded: true,
    dropdownColor: Color(0xFF171717),
    onChanged: onChanged,
    style: TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: tr(context, 'Province'),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    items: kCanadianProvinces.entries.map((entry) {
      return DropdownMenuItem(
        value: entry.key,
        child: Text(
          '${entry.value} (${entry.key})',
          style: TextStyle(fontSize: 13, color: Colors.white),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      );
    }).toList(),
  );
}

Widget _clientFormField({
  required BuildContext context,
  required TextEditingController controller,
  required String hintText,
  int maxLines = 1,
  ValueChanged<String>? onChanged,
}) {
  final isMultiline = maxLines > 1;

  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      style: TextStyle(
        color: Colors.black87,
        fontSize: 15,
      ),
      textAlignVertical:
      isMultiline ? TextAlignVertical.top : TextAlignVertical.center,
      decoration: InputDecoration(
        labelText: tr(context, hintText),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: TextStyle(
          color: Color(0xFF8E8E93),
          fontSize: 14,
        ),
        floatingLabelStyle: TextStyle(
          color: kPurple,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: isMultiline ? 16 : 15,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Color(0xFFE5E5EA),
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: kPurple,
            width: 2,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Color(0xFFE5E5EA),
            width: 1.2,
          ),
        ),
      ),
    ),
  );
}

Widget _clientFormFieldDark({
  required BuildContext context,
  required TextEditingController controller,
  required String hintText,
  int maxLines = 1,
  ValueChanged<String>? onChanged,
}) {
  final isMultiline = maxLines > 1;

  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.35),
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      style: TextStyle(
        color: Colors.white,
        fontSize: 15,
      ),
      textAlignVertical:
      isMultiline ? TextAlignVertical.top : TextAlignVertical.center,
      decoration: InputDecoration(
        labelText: tr(context, hintText),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: TextStyle(
          color: Colors.white38,
          fontSize: 14,
        ),
        floatingLabelStyle: TextStyle(
          color: kPurple,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: Color(0xFF171717),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: isMultiline ? 16 : 15,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Color(0xFF2D2D2D),
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: kPurple,
            width: 2,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Color(0xFF2D2D2D),
            width: 1.2,
          ),
        ),
      ),
    ),
  );
}

Widget _contactsSectionLight({
  required BuildContext context,
  required List<_BusinessContactFormData> contacts,
  required VoidCallback onAddContact,
  required ValueChanged<int> onRemoveContact,
  required VoidCallback onChanged,
}) {
  return Container(
    width: double.infinity,
    padding: EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Color(0xFFF7F4FE),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Color(0xFFE1D7FA)),
    ),
    child: contacts.isEmpty
        ? SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: onAddContact,
        icon: Icon(Icons.add, color: kPurple),
        label: Text(
          tr(context, 'Add new contact'),
          style: TextStyle(color: kPurple),
        ),
        style: TextButton.styleFrom(
          padding: EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: kPurple.withOpacity(0.4)),
          ),
        ),
      ),
    )
        : Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tr(context, 'Business contacts'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Text(
          tr(
            context,
            'Each contact needs a name and a phone number or email',
          ),
          style: TextStyle(
            fontSize: 12,
            color: Colors.black54,
          ),
        ),
        SizedBox(height: 12),
        ...List.generate(
          contacts.length,
              (index) => Padding(
            padding: EdgeInsets.only(
              bottom: index == contacts.length - 1 ? 0 : 12,
            ),
            child: _contactCardLight(
              context: context,
              contact: contacts[index],
              index: index,
              onRemove: () => onRemoveContact(index),
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: onAddContact,
            icon: Icon(Icons.add, color: kPurple),
            label: Text(
              tr(context, 'Add new contact'),
              style: TextStyle(color: kPurple),
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: kPurple.withOpacity(0.4)),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _contactsSectionDark({
  required BuildContext context,
  required List<_BusinessContactFormData> contacts,
  required VoidCallback onAddContact,
  required ValueChanged<int> onRemoveContact,
  required VoidCallback onChanged,
}) {
  return Container(
    width: double.infinity,
    padding: EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Color(0xFF171717),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Color(0xFF2D2D2D)),
    ),
    child: contacts.isEmpty
        ? SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: onAddContact,
        icon: Icon(Icons.add, color: kPurple),
        label: Text(
          tr(context, 'Add new contact'),
          style: TextStyle(color: kPurple),
        ),
        style: TextButton.styleFrom(
          padding: EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: kPurple.withOpacity(0.4)),
          ),
        ),
      ),
    )
        : Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tr(context, 'Business contacts'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Text(
          tr(
            context,
            'Each contact needs a name and a phone number or email',
          ),
          style: TextStyle(
            fontSize: 12,
            color: Colors.white60,
          ),
        ),
        SizedBox(height: 12),
        ...List.generate(
          contacts.length,
              (index) => Padding(
            padding: EdgeInsets.only(
              bottom: index == contacts.length - 1 ? 0 : 12,
            ),
            child: _contactCardDark(
              context: context,
              contact: contacts[index],
              index: index,
              onRemove: () => onRemoveContact(index),
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: onAddContact,
            icon: Icon(Icons.add, color: kPurple),
            label: Text(
              tr(context, 'Add new contact'),
              style: TextStyle(color: kPurple),
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: kPurple.withOpacity(0.4)),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _contactCardLight({
  required BuildContext context,
  required _BusinessContactFormData contact,
  required int index,
  required VoidCallback onRemove,
  required VoidCallback onChanged,
}) {
  return Container(
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Color(0xFFE5E5EA)),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${tr(context, 'Contact')} ${index + 1}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: onRemove,
              icon: Icon(Icons.delete_outline),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        SizedBox(height: 8),
        _clientFormField(
          context: context,
          controller: contact.nameController,
          hintText: 'Contact name',
          onChanged: (_) => onChanged(),
        ),
        SizedBox(height: 10),
        _clientFormField(
          context: context,
          controller: contact.phoneController,
          hintText: 'Contact phone',
          onChanged: (_) => onChanged(),
        ),
        SizedBox(height: 10),
        _clientFormField(
          context: context,
          controller: contact.emailController,
          hintText: 'Contact email',
          onChanged: (_) => onChanged(),
        ),
      ],
    ),
  );
}

Widget _contactCardDark({
  required BuildContext context,
  required _BusinessContactFormData contact,
  required int index,
  required VoidCallback onRemove,
  required VoidCallback onChanged,
}) {
  return Container(
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Color(0xFF111111),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Color(0xFF2A2A2A)),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${tr(context, 'Contact')} ${index + 1}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            IconButton(
              onPressed: onRemove,
              icon: Icon(Icons.delete_outline, color: Colors.white70),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        SizedBox(height: 8),
        _clientFormFieldDark(
          context: context,
          controller: contact.nameController,
          hintText: 'Contact name',
          onChanged: (_) => onChanged(),
        ),
        SizedBox(height: 10),
        _clientFormFieldDark(
          context: context,
          controller: contact.phoneController,
          hintText: 'Contact phone',
          onChanged: (_) => onChanged(),
        ),
        SizedBox(height: 10),
        _clientFormFieldDark(
          context: context,
          controller: contact.emailController,
          hintText: 'Contact email',
          onChanged: (_) => onChanged(),
        ),
      ],
    ),
  );
}

class _ClientCard extends StatelessWidget {
  final ClientRecord client;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ClientCard({
    required this.client,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final title =
    client.businessName.isNotEmpty ? client.businessName : client.name;
    final subtitle = client.phone.isNotEmpty
        ? client.phone
        : client.email;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: Color(0xFFDCD4F8),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                    if (client.businessName.isNotEmpty && client.contacts.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          '${client.contacts.length} ${tr(context, 'contacts')}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
                icon: Icon(Icons.edit_outlined, size: 20),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientCardDark extends StatelessWidget {
  final ClientRecord client;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ClientCardDark({
    required this.client,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final title =
    client.businessName.isNotEmpty ? client.businessName : client.name;
    final subtitle = client.phone.isNotEmpty
        ? client.phone
        : client.email;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: Color(0xFF171717),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Color(0xFF2A2A2A)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white60,
                      ),
                    ),
                    if (client.businessName.isNotEmpty && client.contacts.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          '${client.contacts.length} ${tr(context, 'contacts')}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white60,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
                icon: Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: Colors.white70,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _clientDetailField({
  required String value,
  int maxLines = 1,
}) {
  return Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    decoration: BoxDecoration(
      color: Color(0xFFF3F3F3),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Color(0xFFD2D2D2)),
    ),
    child: Text(
      value,
      maxLines: maxLines,
      overflow: maxLines == 1 ? TextOverflow.ellipsis : TextOverflow.visible,
      style: TextStyle(
        fontSize: 15,
        color: Color(0xFF7A7A7A),
        fontWeight: FontWeight.w400,
      ),
    ),
  );
}

Widget _clientDetailFieldDark({
  required String value,
  int maxLines = 1,
}) {
  return Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    decoration: BoxDecoration(
      color: Color(0xFF171717),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Color(0xFF2D2D2D)),
    ),
    child: Text(
      value,
      maxLines: maxLines,
      overflow: maxLines == 1 ? TextOverflow.ellipsis : TextOverflow.visible,
      style: TextStyle(
        fontSize: 15,
        color: Colors.white70,
        fontWeight: FontWeight.w400,
      ),
    ),
  );
}


Widget _clientDetailSectionLabel({
  required BuildContext context,
  required String label,
}) {
  return Align(
    alignment: Alignment.centerLeft,
    child: Text(
      tr(context, label),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    ),
  );
}


Map<String, String> _splitAddressParts(String address) {
  final parts = address
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();

  String street = '';
  String city = '';
  String province = 'QC';
  String postalCode = '';

  if (parts.isNotEmpty) {
    street = parts[0];
  }
  if (parts.length > 1) {
    city = parts[1];
  }
  if (parts.length > 2) {
    final provincePostal = parts[2].split(RegExp(r'\s+'));
    if (provincePostal.isNotEmpty && provincePostal.first.isNotEmpty) {
      final provinceCandidate = provincePostal.first.toUpperCase();
      if (kCanadianProvinces.containsKey(provinceCandidate)) {
        province = provinceCandidate;
      }
    }
    if (provincePostal.length > 1) {
      postalCode = provincePostal.sublist(1).join(' ').trim();
    }
  }
  if (parts.length > 3) {
    postalCode = parts.sublist(3).join(', ').trim();
  }

  return {
    'street': street,
    'city': city,
    'province': province,
    'postalCode': postalCode,
  };
}

Widget _clientDetailSectionLabelDark({
  required BuildContext context,
  required String label,
}) {
  return Align(
    alignment: Alignment.centerLeft,
    child: Text(
      tr(context, label),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
  );
}

Future<void> showEditClientPopup(
    BuildContext context, {
      required ClientRecord client,
    }) async {
  final businessNameController =
  TextEditingController(text: client.businessName);
  final nameController = TextEditingController(text: client.name);
  final addressSearchController = TextEditingController();
  final addressParts = _splitAddressParts(client.address);
  final streetController =
  TextEditingController(text: addressParts['street'] ?? '');
  final cityController =
  TextEditingController(text: addressParts['city'] ?? '');
  String selectedProvince = addressParts['province'] ?? 'QC';
  final postalCodeController =
  TextEditingController(text: addressParts['postalCode'] ?? '');
  final phoneController = TextEditingController(text: client.phone);
  final emailController = TextEditingController(text: client.email);

  if (client.address.trim().isNotEmpty) {
    addressSearchController.text = client.address.trim();
  }

  final contacts = client.contacts
      .map(
        (contact) => _BusinessContactFormData(
      name: contact.name,
      phone: contact.phone,
      email: contact.email,
    ),
  )
      .toList();

  if (contacts.isEmpty && client.businessName.isNotEmpty) {
    contacts.add(_BusinessContactFormData());
  }

  bool isSaving = false;
  String? popupError;
  List<AddressSuggestion> addressSuggestions = [];
  bool showAddressSuggestions = false;
  bool isLoadingAddressSuggestions = false;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setPopupState) {
          final isBusinessClient = businessNameController.text.trim().isNotEmpty;

          void clearError() {
            if (popupError != null) {
              setPopupState(() {
                popupError = null;
              });
            }
          }

          Future<void> searchAddresses(String value) async {
            if (value.trim().isEmpty) {
              setPopupState(() {
                addressSuggestions = [];
                showAddressSuggestions = false;
                isLoadingAddressSuggestions = false;
              });
              return;
            }

            setPopupState(() {
              showAddressSuggestions = true;
              isLoadingAddressSuggestions = true;
            });

            try {
              final results = await GooglePlacesService.autocomplete(value);

              if (!context.mounted) return;

              setPopupState(() {
                addressSuggestions = results;
                isLoadingAddressSuggestions = false;
              });
            } catch (_) {
              if (!context.mounted) return;

              setPopupState(() {
                addressSuggestions = [];
                isLoadingAddressSuggestions = false;
                showAddressSuggestions = true;
              });
            }
          }

          Future<void> selectAddress(AddressSuggestion suggestion) async {
            final details =
            await GooglePlacesService.getPlaceDetails(suggestion.placeId);

            if (!context.mounted) return;

            setPopupState(() {
              addressSearchController.text = details.fullAddress;
              streetController.text = details.street;
              cityController.text = details.city;
              selectedProvince = details.province.isNotEmpty &&
                  kCanadianProvinces.containsKey(details.province)
                  ? details.province
                  : 'QC';
              postalCodeController.text = details.postalCode;
              showAddressSuggestions = false;
            });
          }

          void addContact() {
            setPopupState(() {
              contacts.add(_BusinessContactFormData());
            });
          }

          void removeContact(int index) {
            final removed = contacts.removeAt(index);
            removed.dispose();
            setPopupState(() {});
          }

          Future<void> updateClient() async {
            final updatedBusinessName = businessNameController.text.trim();
            final updatedName = nameController.text.trim();
            final updatedStreet = streetController.text.trim();
            final updatedCity = cityController.text.trim();
            final updatedProvince = selectedProvince.trim();
            final updatedPostalCode = postalCodeController.text.trim();
            final updatedAddress = [
              updatedStreet,
              updatedCity,
              updatedProvince,
              updatedPostalCode,
            ].where((e) => e.isNotEmpty).join(', ');
            final updatedPhone = phoneController.text.trim();
            final updatedEmail = emailController.text.trim();

            final addressRequired = updatedBusinessName.isEmpty;

            if (updatedBusinessName.isEmpty && updatedName.isEmpty) {
              setPopupState(() {
                popupError = tr(
                  context,
                  'Business name or name is required',
                );
              });
              return;
            }

            if (updatedPhone.isEmpty && updatedEmail.isEmpty) {
              setPopupState(() {
                popupError = tr(
                  context,
                  'Either phone number or email is required',
                );
              });
              return;
            }

            if (addressRequired &&
                (updatedStreet.isEmpty ||
                    updatedCity.isEmpty ||
                    updatedProvince.isEmpty ||
                    updatedPostalCode.isEmpty)) {
              setPopupState(() {
                popupError = tr(
                  context,
                  'Address is required when no business name is entered',
                );
              });
              return;
            }

            final cleanedContacts = contacts
                .where((c) => !c.isCompletelyEmpty)
                .map((c) => c.toClientContact())
                .toList();

            final hasInvalidContact = contacts.any(
                  (c) => !c.isCompletelyEmpty && !c.isValid,
            );

            if (hasInvalidContact) {
              setPopupState(() {
                popupError = tr(
                  context,
                  'Each contact must have a name and a phone number or email',
                );
              });
              return;
            }

            setPopupState(() {
              popupError = null;
              isSaving = true;
            });

            try {
              await ClientService.updateClient(
                id: client.id,
                businessName: updatedBusinessName,
                name: updatedName,
                address: updatedAddress,
                phone: updatedPhone,
                email: updatedEmail,
                contacts: cleanedContacts,
              );

              if (context.mounted) {
                Navigator.pop(context);
              }
            } catch (e) {
              if (!context.mounted) return;

              setPopupState(() {
                popupError = '${tr(context, 'Error')}: $e';
                isSaving = false;
              });
            } finally {
              if (context.mounted) {
                setPopupState(() {
                  isSaving = false;
                });
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.fromLTRB(18, 12, 18, 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 44,
                      child: Divider(
                        thickness: 4,
                        color: Color(0xFFD0D0D0),
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      tr(context, 'Edit Client'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 18),
                    _clientFormField(
                      context: context,
                      controller: businessNameController,
                      hintText: 'Business name',
                      onChanged: (_) {
                        clearError();
                        setPopupState(() {});
                      },
                    ),
                    SizedBox(height: 12),
                    _clientFormField(
                      context: context,
                      controller: nameController,
                      hintText: 'Name',
                      onChanged: (_) => clearError(),
                    ),
                    SizedBox(height: 12),
                    _clientFormField(
                      context: context,
                      controller: addressSearchController,
                      hintText: 'Search address',
                      onChanged: (value) {
                        clearError();
                        searchAddresses(value);
                      },
                    ),
                    if (showAddressSuggestions)
                      Container(
                        margin: EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Color(0xFFE0E0E0)),
                        ),
                        constraints: BoxConstraints(maxHeight: 220),
                        child: isLoadingAddressSuggestions
                            ? Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        )
                            : addressSuggestions.isEmpty
                            ? Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            tr(context, 'No address found'),
                            style: TextStyle(color: Colors.black54),
                          ),
                        )
                            : ListView.builder(
                          shrinkWrap: true,
                          itemCount: addressSuggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion =
                            addressSuggestions[index];
                            return ListTile(
                              title: Text(suggestion.description),
                              onTap: () => selectAddress(suggestion),
                            );
                          },
                        ),
                      ),
                    SizedBox(height: 12),
                    _clientFormField(
                      context: context,
                      controller: streetController,
                      hintText: 'Street',
                      onChanged: (_) => clearError(),
                    ),
                    SizedBox(height: 12),
                    _clientFormField(
                      context: context,
                      controller: cityController,
                      hintText: 'City',
                      onChanged: (_) => clearError(),
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _clientFormField(
                            context: context,
                            controller: postalCodeController,
                            hintText: 'Postal code',
                            onChanged: (_) => clearError(),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: _provinceDropdownField(
                            context: context,
                            value: selectedProvince,
                            onChanged: (value) {
                              if (value == null) return;
                              clearError();
                              setPopupState(() {
                                selectedProvince = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    _clientFormField(
                      context: context,
                      controller: phoneController,
                      hintText: 'Phone number',
                      onChanged: (_) => clearError(),
                    ),
                    SizedBox(height: 12),
                    _clientFormField(
                      context: context,
                      controller: emailController,
                      hintText: 'Email',
                      onChanged: (_) => clearError(),
                    ),
                    if (isBusinessClient) ...[
                      SizedBox(height: 18),
                      _contactsSectionLight(
                        context: context,
                        contacts: contacts,
                        onAddContact: addContact,
                        onRemoveContact: removeContact,
                        onChanged: clearError,
                      ),
                    ],
                    if (popupError != null) ...[
                      SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Color(0xFFFFEAEA),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Color(0xFFFFB3B3)),
                        ),
                        child: Text(
                          popupError!,
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isSaving ? null : updateClient,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: isSaving
                            ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                            : Text(tr(context, 'Update Client')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  Future.delayed(Duration(milliseconds: 100), () {
    businessNameController.dispose();
    nameController.dispose();
    addressSearchController.dispose();
    streetController.dispose();
    cityController.dispose();
    postalCodeController.dispose();
    phoneController.dispose();
    emailController.dispose();
    for (final contact in contacts) {
      contact.dispose();
    }
  });
}

Future<void> showEditClientDarkPopup(
    BuildContext context, {
      required ClientRecord client,
    }) async {
  final businessNameController =
  TextEditingController(text: client.businessName);
  final nameController = TextEditingController(text: client.name);
  final addressSearchController = TextEditingController();
  final addressParts = _splitAddressParts(client.address);
  final streetController =
  TextEditingController(text: addressParts['street'] ?? '');
  final cityController =
  TextEditingController(text: addressParts['city'] ?? '');
  String selectedProvince = addressParts['province'] ?? 'QC';
  final postalCodeController =
  TextEditingController(text: addressParts['postalCode'] ?? '');
  final phoneController = TextEditingController(text: client.phone);
  final emailController = TextEditingController(text: client.email);

  if (client.address.trim().isNotEmpty) {
    addressSearchController.text = client.address.trim();
  }

  final contacts = client.contacts
      .map(
        (contact) => _BusinessContactFormData(
      name: contact.name,
      phone: contact.phone,
      email: contact.email,
    ),
  )
      .toList();

  if (contacts.isEmpty && client.businessName.isNotEmpty) {
    contacts.add(_BusinessContactFormData());
  }

  bool isSaving = false;
  String? popupError;
  List<AddressSuggestion> addressSuggestions = [];
  bool showAddressSuggestions = false;
  bool isLoadingAddressSuggestions = false;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setPopupState) {
          final isBusinessClient = businessNameController.text.trim().isNotEmpty;

          void clearError() {
            if (popupError != null) {
              setPopupState(() {
                popupError = null;
              });
            }
          }

          Future<void> searchAddresses(String value) async {
            if (value.trim().isEmpty) {
              setPopupState(() {
                addressSuggestions = [];
                showAddressSuggestions = false;
                isLoadingAddressSuggestions = false;
              });
              return;
            }

            setPopupState(() {
              showAddressSuggestions = true;
              isLoadingAddressSuggestions = true;
            });

            try {
              final results = await GooglePlacesService.autocomplete(value);

              if (!context.mounted) return;

              setPopupState(() {
                addressSuggestions = results;
                isLoadingAddressSuggestions = false;
              });
            } catch (_) {
              if (!context.mounted) return;

              setPopupState(() {
                addressSuggestions = [];
                isLoadingAddressSuggestions = false;
                showAddressSuggestions = true;
              });
            }
          }

          Future<void> selectAddress(AddressSuggestion suggestion) async {
            final details =
            await GooglePlacesService.getPlaceDetails(suggestion.placeId);

            if (!context.mounted) return;

            setPopupState(() {
              addressSearchController.text = details.fullAddress;
              streetController.text = details.street;
              cityController.text = details.city;
              selectedProvince = details.province.isNotEmpty &&
                  kCanadianProvinces.containsKey(details.province)
                  ? details.province
                  : 'QC';
              postalCodeController.text = details.postalCode;
              showAddressSuggestions = false;
            });
          }

          void addContact() {
            setPopupState(() {
              contacts.add(_BusinessContactFormData());
            });
          }

          void removeContact(int index) {
            final removed = contacts.removeAt(index);
            removed.dispose();
            setPopupState(() {});
          }

          Future<void> updateClient() async {
            final updatedBusinessName = businessNameController.text.trim();
            final updatedName = nameController.text.trim();
            final updatedStreet = streetController.text.trim();
            final updatedCity = cityController.text.trim();
            final updatedProvince = selectedProvince.trim();
            final updatedPostalCode = postalCodeController.text.trim();
            final updatedAddress = [
              updatedStreet,
              updatedCity,
              updatedProvince,
              updatedPostalCode,
            ].where((e) => e.isNotEmpty).join(', ');
            final updatedPhone = phoneController.text.trim();
            final updatedEmail = emailController.text.trim();

            final addressRequired = updatedBusinessName.isEmpty;

            if (updatedBusinessName.isEmpty && updatedName.isEmpty) {
              setPopupState(() {
                popupError = tr(
                  context,
                  'Business name or name is required',
                );
              });
              return;
            }

            if (updatedPhone.isEmpty && updatedEmail.isEmpty) {
              setPopupState(() {
                popupError = tr(
                  context,
                  'Either phone number or email is required',
                );
              });
              return;
            }

            if (addressRequired &&
                (updatedStreet.isEmpty ||
                    updatedCity.isEmpty ||
                    updatedProvince.isEmpty ||
                    updatedPostalCode.isEmpty)) {
              setPopupState(() {
                popupError = tr(
                  context,
                  'Address is required when no business name is entered',
                );
              });
              return;
            }

            final cleanedContacts = contacts
                .where((c) => !c.isCompletelyEmpty)
                .map((c) => c.toClientContact())
                .toList();

            final hasInvalidContact = contacts.any(
                  (c) => !c.isCompletelyEmpty && !c.isValid,
            );

            if (hasInvalidContact) {
              setPopupState(() {
                popupError = tr(
                  context,
                  'Each contact must have a name and a phone number or email',
                );
              });
              return;
            }

            setPopupState(() {
              popupError = null;
              isSaving = true;
            });

            try {
              await ClientService.updateClient(
                id: client.id,
                businessName: updatedBusinessName,
                name: updatedName,
                address: updatedAddress,
                phone: updatedPhone,
                email: updatedEmail,
                contacts: cleanedContacts,
              );

              if (context.mounted) {
                Navigator.pop(context);
              }
            } catch (e) {
              if (!context.mounted) return;

              setPopupState(() {
                popupError = '${tr(context, 'Error')}: $e';
                isSaving = false;
              });
            } finally {
              if (context.mounted) {
                setPopupState(() {
                  isSaving = false;
                });
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.fromLTRB(18, 12, 18, 22),
                decoration: BoxDecoration(
                  color: Color(0xFF121212),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 44,
                      child: Divider(
                        thickness: 4,
                        color: Color(0xFF3A3A3A),
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      tr(context, 'Edit Client'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 18),
                    _clientFormFieldDark(
                      context: context,
                      controller: businessNameController,
                      hintText: 'Business name',
                      onChanged: (_) {
                        clearError();
                        setPopupState(() {});
                      },
                    ),
                    SizedBox(height: 12),
                    _clientFormFieldDark(
                      context: context,
                      controller: nameController,
                      hintText: 'Name',
                      onChanged: (_) => clearError(),
                    ),
                    SizedBox(height: 12),
                    _clientFormFieldDark(
                      context: context,
                      controller: addressSearchController,
                      hintText: 'Search address',
                      onChanged: (value) {
                        clearError();
                        searchAddresses(value);
                      },
                    ),
                    if (showAddressSuggestions)
                      Container(
                        margin: EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: Color(0xFF171717),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Color(0xFF2D2D2D)),
                        ),
                        constraints: BoxConstraints(maxHeight: 220),
                        child: isLoadingAddressSuggestions
                            ? Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        )
                            : addressSuggestions.isEmpty
                            ? Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            tr(context, 'No address found'),
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                            : ListView.builder(
                          shrinkWrap: true,
                          itemCount: addressSuggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion =
                            addressSuggestions[index];
                            return ListTile(
                              title: Text(
                                suggestion.description,
                                style: TextStyle(color: Colors.white),
                              ),
                              onTap: () => selectAddress(suggestion),
                            );
                          },
                        ),
                      ),
                    SizedBox(height: 12),
                    _clientFormFieldDark(
                      context: context,
                      controller: streetController,
                      hintText: 'Street',
                      onChanged: (_) => clearError(),
                    ),
                    SizedBox(height: 12),
                    _clientFormFieldDark(
                      context: context,
                      controller: cityController,
                      hintText: 'City',
                      onChanged: (_) => clearError(),
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _clientFormFieldDark(
                            context: context,
                            controller: postalCodeController,
                            hintText: 'Postal code',
                            onChanged: (_) => clearError(),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: _provinceDropdownFieldDark(
                            context: context,
                            value: selectedProvince,
                            onChanged: (value) {
                              if (value == null) return;
                              clearError();
                              setPopupState(() {
                                selectedProvince = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    _clientFormFieldDark(
                      context: context,
                      controller: phoneController,
                      hintText: 'Phone number',
                      onChanged: (_) => clearError(),
                    ),
                    SizedBox(height: 12),
                    _clientFormFieldDark(
                      context: context,
                      controller: emailController,
                      hintText: 'Email',
                      onChanged: (_) => clearError(),
                    ),
                    if (isBusinessClient) ...[
                      SizedBox(height: 18),
                      _contactsSectionDark(
                        context: context,
                        contacts: contacts,
                        onAddContact: addContact,
                        onRemoveContact: removeContact,
                        onChanged: clearError,
                      ),
                    ],
                    if (popupError != null) ...[
                      SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Color(0xFF2A1212),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Color(0xFF5A2A2A)),
                        ),
                        child: Text(
                          popupError!,
                          style: TextStyle(
                            color: Color(0xFFFF8A8A),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isSaving ? null : updateClient,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: isSaving
                            ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                            : Text(tr(context, 'Update Client')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  Future.delayed(Duration(milliseconds: 100), () {
    businessNameController.dispose();
    nameController.dispose();
    addressSearchController.dispose();
    streetController.dispose();
    cityController.dispose();
    postalCodeController.dispose();
    phoneController.dispose();
    emailController.dispose();
    for (final contact in contacts) {
      contact.dispose();
    }
  });
}

Future<void> showClientDetailsPopup(BuildContext context, {
  required ClientRecord client,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 22),
          decoration: BoxDecoration(
            color: Color(0xFFF3F3F3),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Color(0xFFD1D1D1),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              SizedBox(height: 18),
              Text(
                tr(context, 'Client details'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              SizedBox(height: 20),
              if (client.businessName.isNotEmpty) ...[
                _clientDetailSectionLabel(
                  context: context,
                  label: 'Business name',
                ),
                SizedBox(height: 6),
                _clientDetailField(value: client.businessName),
                SizedBox(height: 12),
              ],
              if (client.name.isNotEmpty) ...[
                _clientDetailSectionLabel(
                  context: context,
                  label: 'Name',
                ),
                SizedBox(height: 6),
                _clientDetailField(value: client.name),
                SizedBox(height: 12),
              ],
              if (client.address.isNotEmpty) ...[
                _clientDetailSectionLabel(
                  context: context,
                  label: 'Address',
                ),
                SizedBox(height: 6),
                _clientDetailField(
                  value: client.address,
                  maxLines: 3,
                ),
                SizedBox(height: 12),
              ],
              if (client.phone.isNotEmpty) ...[
                _clientDetailSectionLabel(
                  context: context,
                  label: 'Phone number',
                ),
                SizedBox(height: 6),
                _clientDetailField(value: client.phone),
                SizedBox(height: 12),
              ],
              if (client.email.isNotEmpty) ...[
                _clientDetailSectionLabel(
                  context: context,
                  label: 'Email',
                ),
                SizedBox(height: 6),
                _clientDetailField(value: client.email),
              ],
              if (client.businessName.isNotEmpty && client.contacts.isNotEmpty) ...[
                SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr(context, 'Business contacts'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(height: 10),
                ...client.contacts.map(
                      (contact) => Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Color(0xFFDCDCDC)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            contact.name.isEmpty
                                ? tr(context, 'Unnamed contact')
                                : contact.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (contact.phone.isNotEmpty) ...[
                            SizedBox(height: 6),
                            Text(
                              '${tr(context, 'Phone number')}: ${contact.phone}',
                            ),
                          ],
                          if (contact.email.isNotEmpty) ...[
                            SizedBox(height: 6),
                            Text(
                              '${tr(context, 'Email')}: ${contact.email}',
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showClientDetailsDarkPopup(BuildContext context, {
  required ClientRecord client,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 22),
          decoration: BoxDecoration(
            color: Color(0xFF121212),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Color(0xFF2A2A2A)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Color(0xFF3A3A3A),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              SizedBox(height: 18),
              Text(
                tr(context, 'Client details'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 20),
              if (client.businessName.isNotEmpty) ...[
                _clientDetailSectionLabelDark(
                  context: context,
                  label: 'Business name',
                ),
                SizedBox(height: 6),
                _clientDetailFieldDark(value: client.businessName),
                SizedBox(height: 12),
              ],
              if (client.name.isNotEmpty) ...[
                _clientDetailSectionLabelDark(
                  context: context,
                  label: 'Name',
                ),
                SizedBox(height: 6),
                _clientDetailFieldDark(value: client.name),
                SizedBox(height: 12),
              ],
              if (client.address.isNotEmpty) ...[
                _clientDetailSectionLabelDark(
                  context: context,
                  label: 'Address',
                ),
                SizedBox(height: 6),
                _clientDetailFieldDark(
                  value: client.address,
                  maxLines: 3,
                ),
                SizedBox(height: 12),
              ],
              if (client.phone.isNotEmpty) ...[
                _clientDetailSectionLabelDark(
                  context: context,
                  label: 'Phone number',
                ),
                SizedBox(height: 6),
                _clientDetailFieldDark(value: client.phone),
                SizedBox(height: 12),
              ],
              if (client.email.isNotEmpty) ...[
                _clientDetailSectionLabelDark(
                  context: context,
                  label: 'Email',
                ),
                SizedBox(height: 6),
                _clientDetailFieldDark(value: client.email),
              ],
              if (client.businessName.isNotEmpty && client.contacts.isNotEmpty) ...[
                SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr(context, 'Business contacts'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                SizedBox(height: 10),
                ...client.contacts.map(
                      (contact) => Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Color(0xFF171717),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Color(0xFF2D2D2D)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            contact.name.isEmpty
                                ? tr(context, 'Unnamed contact')
                                : contact.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          if (contact.phone.isNotEmpty) ...[
                            SizedBox(height: 6),
                            Text(
                              '${tr(context, 'Phone number')}: ${contact.phone}',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                          if (contact.email.isNotEmpty) ...[
                            SizedBox(height: 6),
                            Text(
                              '${tr(context, 'Email')}: ${contact.email}',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
