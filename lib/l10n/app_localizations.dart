import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr')
  ];

  /// No description provided for @schedulingApp.
  ///
  /// In en, this message translates to:
  /// **'Scheduling App'**
  String get schedulingApp;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @enterEmailAndPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter email and password'**
  String get enterEmailAndPassword;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPassword;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signIn;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get or;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @createAccount2.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccount2;

  /// No description provided for @signIn2.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn2;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @invited.
  ///
  /// In en, this message translates to:
  /// **'Invited'**
  String get invited;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @menu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menu;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logOut;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @size.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get size;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @calendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendar;

  /// No description provided for @employees.
  ///
  /// In en, this message translates to:
  /// **'Employees'**
  String get employees;

  /// No description provided for @clients.
  ///
  /// In en, this message translates to:
  /// **'Clients'**
  String get clients;

  /// No description provided for @appointments.
  ///
  /// In en, this message translates to:
  /// **'Appointments'**
  String get appointments;

  /// No description provided for @changeFontSize.
  ///
  /// In en, this message translates to:
  /// **'Change Font Size'**
  String get changeFontSize;

  /// No description provided for @changeToDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Change to Dark Mode'**
  String get changeToDarkMode;

  /// No description provided for @changeToLightMode.
  ///
  /// In en, this message translates to:
  /// **'Change to Light Mode'**
  String get changeToLightMode;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose Language'**
  String get chooseLanguage;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @french.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get french;

  /// No description provided for @textSize.
  ///
  /// In en, this message translates to:
  /// **'Text Size'**
  String get textSize;

  /// No description provided for @previewText.
  ///
  /// In en, this message translates to:
  /// **'Preview text'**
  String get previewText;

  /// No description provided for @lightMode.
  ///
  /// In en, this message translates to:
  /// **'Light Mode'**
  String get lightMode;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @hello.
  ///
  /// In en, this message translates to:
  /// **'Hello'**
  String get hello;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @end.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get end;

  /// No description provided for @francais.
  ///
  /// In en, this message translates to:
  /// **'Français'**
  String get francais;

  /// No description provided for @editEmployees.
  ///
  /// In en, this message translates to:
  /// **'Edit Employees'**
  String get editEmployees;

  /// No description provided for @searchByNameOrPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Search by name or phone number'**
  String get searchByNameOrPhoneNumber;

  /// No description provided for @searchByNameOrPhoneNumber2.
  ///
  /// In en, this message translates to:
  /// **'Search by name or phone number...'**
  String get searchByNameOrPhoneNumber2;

  /// No description provided for @createEmployee.
  ///
  /// In en, this message translates to:
  /// **'Create Employee'**
  String get createEmployee;

  /// No description provided for @enterUsernameAndEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter username and email'**
  String get enterUsernameAndEmail;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @value.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get value;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumber;

  /// No description provided for @employeeColor.
  ///
  /// In en, this message translates to:
  /// **'Employee Color'**
  String get employeeColor;

  /// No description provided for @employeeName.
  ///
  /// In en, this message translates to:
  /// **'Employee name'**
  String get employeeName;

  /// No description provided for @editEmployee.
  ///
  /// In en, this message translates to:
  /// **'Edit Employee'**
  String get editEmployee;

  /// No description provided for @updateEmployee.
  ///
  /// In en, this message translates to:
  /// **'Update Employee'**
  String get updateEmployee;

  /// No description provided for @employeeDetails.
  ///
  /// In en, this message translates to:
  /// **'Employee details'**
  String get employeeDetails;

  /// No description provided for @employeeColor2.
  ///
  /// In en, this message translates to:
  /// **'Employee color'**
  String get employeeColor2;

  /// No description provided for @editClients.
  ///
  /// In en, this message translates to:
  /// **'Edit Clients'**
  String get editClients;

  /// No description provided for @addClient.
  ///
  /// In en, this message translates to:
  /// **'Add Client'**
  String get addClient;

  /// No description provided for @clientName.
  ///
  /// In en, this message translates to:
  /// **'Client name'**
  String get clientName;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @businessName.
  ///
  /// In en, this message translates to:
  /// **'Business name'**
  String get businessName;

  /// No description provided for @contactName.
  ///
  /// In en, this message translates to:
  /// **'Contact name'**
  String get contactName;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @aptUnit.
  ///
  /// In en, this message translates to:
  /// **'Apt / Unit'**
  String get aptUnit;

  /// No description provided for @city.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get city;

  /// No description provided for @province.
  ///
  /// In en, this message translates to:
  /// **'Province'**
  String get province;

  /// No description provided for @postalCode.
  ///
  /// In en, this message translates to:
  /// **'Postal code'**
  String get postalCode;

  /// No description provided for @country.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get country;

  /// No description provided for @editClient.
  ///
  /// In en, this message translates to:
  /// **'Edit Client'**
  String get editClient;

  /// No description provided for @editClient2.
  ///
  /// In en, this message translates to:
  /// **'Edit client'**
  String get editClient2;

  /// No description provided for @updateClient.
  ///
  /// In en, this message translates to:
  /// **'Update Client'**
  String get updateClient;

  /// No description provided for @clientDetails.
  ///
  /// In en, this message translates to:
  /// **'Client details'**
  String get clientDetails;

  /// No description provided for @contacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get contacts;

  /// No description provided for @newClient.
  ///
  /// In en, this message translates to:
  /// **'New client'**
  String get newClient;

  /// No description provided for @addClient2.
  ///
  /// In en, this message translates to:
  /// **'Add client'**
  String get addClient2;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @deleting.
  ///
  /// In en, this message translates to:
  /// **'Deleting...'**
  String get deleting;

  /// No description provided for @deleteClient.
  ///
  /// In en, this message translates to:
  /// **'Delete client?'**
  String get deleteClient;

  /// No description provided for @areYouSureYouWantToDelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete'**
  String get areYouSureYouWantToDelete;

  /// No description provided for @thisCannotBeUndone.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get thisCannotBeUndone;

  /// No description provided for @clientDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Client deleted successfully.'**
  String get clientDeletedSuccessfully;

  /// No description provided for @couldNotDeleteClientTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Could not delete client. Try again.'**
  String get couldNotDeleteClientTryAgain;

  /// No description provided for @couldNotSaveChangesTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Could not save changes. Try again.'**
  String get couldNotSaveChangesTryAgain;

  /// No description provided for @couldNotAddClientTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Could not add client. Try again.'**
  String get couldNotAddClientTryAgain;

  /// No description provided for @thisClient.
  ///
  /// In en, this message translates to:
  /// **'this client'**
  String get thisClient;

  /// No description provided for @additionalBusinessContacts.
  ///
  /// In en, this message translates to:
  /// **'Additional business contacts'**
  String get additionalBusinessContacts;

  /// No description provided for @theFirstContactIsTheMainContactAboveAddMoreContactsHereIfNeeded.
  ///
  /// In en, this message translates to:
  /// **'The first contact is the main contact above. Add more contacts here if needed.'**
  String get theFirstContactIsTheMainContactAboveAddMoreContactsHereIfNeeded;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @addAnotherContact.
  ///
  /// In en, this message translates to:
  /// **'Add another contact'**
  String get addAnotherContact;

  /// No description provided for @contact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get contact;

  /// No description provided for @removeContact.
  ///
  /// In en, this message translates to:
  /// **'Remove contact'**
  String get removeContact;

  /// No description provided for @contactNameIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Contact name is required'**
  String get contactNameIsRequired;

  /// No description provided for @businessNameOrContactNameIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Business name or contact name is required'**
  String get businessNameOrContactNameIsRequired;

  /// No description provided for @phoneOrEmailIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone or email is required'**
  String get phoneOrEmailIsRequired;

  /// No description provided for @addressIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Address is required'**
  String get addressIsRequired;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'name'**
  String get name;

  /// No description provided for @name2.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name2;

  /// No description provided for @event.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get event;

  /// No description provided for @eventName.
  ///
  /// In en, this message translates to:
  /// **'Event name'**
  String get eventName;

  /// No description provided for @eventName2.
  ///
  /// In en, this message translates to:
  /// **'Event name*'**
  String get eventName2;

  /// No description provided for @titleIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Title is required'**
  String get titleIsRequired;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @selectDate.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get selectDate;

  /// No description provided for @startTime.
  ///
  /// In en, this message translates to:
  /// **'Start Time'**
  String get startTime;

  /// No description provided for @endTime.
  ///
  /// In en, this message translates to:
  /// **'End Time'**
  String get endTime;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// No description provided for @client.
  ///
  /// In en, this message translates to:
  /// **'Client'**
  String get client;

  /// No description provided for @clientSearchByNameOrPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Client (search by name or phone number)'**
  String get clientSearchByNameOrPhoneNumber;

  /// No description provided for @clientNamePhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Client name (phone number)'**
  String get clientNamePhoneNumber;

  /// No description provided for @typeOfJob.
  ///
  /// In en, this message translates to:
  /// **'Type of job'**
  String get typeOfJob;

  /// No description provided for @typeOfJob2.
  ///
  /// In en, this message translates to:
  /// **'Type of job...'**
  String get typeOfJob2;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @materialsNeeded.
  ///
  /// In en, this message translates to:
  /// **'Materials needed'**
  String get materialsNeeded;

  /// No description provided for @pictures.
  ///
  /// In en, this message translates to:
  /// **'Pictures'**
  String get pictures;

  /// No description provided for @addNewEvent.
  ///
  /// In en, this message translates to:
  /// **'Add New Event'**
  String get addNewEvent;

  /// No description provided for @addNewJob.
  ///
  /// In en, this message translates to:
  /// **'Add New Job'**
  String get addNewJob;

  /// No description provided for @jobTitle.
  ///
  /// In en, this message translates to:
  /// **'Job Title'**
  String get jobTitle;

  /// No description provided for @jobTitle2.
  ///
  /// In en, this message translates to:
  /// **'Job title'**
  String get jobTitle2;

  /// No description provided for @createEvent.
  ///
  /// In en, this message translates to:
  /// **'Create Event'**
  String get createEvent;

  /// No description provided for @createEvent2.
  ///
  /// In en, this message translates to:
  /// **'Create event'**
  String get createEvent2;

  /// No description provided for @editEvent.
  ///
  /// In en, this message translates to:
  /// **'Edit Event'**
  String get editEvent;

  /// No description provided for @updateEvent.
  ///
  /// In en, this message translates to:
  /// **'Update Event'**
  String get updateEvent;

  /// No description provided for @editJob.
  ///
  /// In en, this message translates to:
  /// **'Edit job'**
  String get editJob;

  /// No description provided for @typeTheNoteHere.
  ///
  /// In en, this message translates to:
  /// **'Type the note here...'**
  String get typeTheNoteHere;

  /// No description provided for @typeTheMaterialsHere.
  ///
  /// In en, this message translates to:
  /// **'Type the materials here...'**
  String get typeTheMaterialsHere;

  /// No description provided for @eGPlumbingRepair.
  ///
  /// In en, this message translates to:
  /// **'e.g. Plumbing repair'**
  String get eGPlumbingRepair;

  /// No description provided for @eGPipeWrenchTapeCommaSeparated.
  ///
  /// In en, this message translates to:
  /// **'e.g. Pipe wrench, tape (comma separated)'**
  String get eGPipeWrenchTapeCommaSeparated;

  /// No description provided for @insertPicturesHere.
  ///
  /// In en, this message translates to:
  /// **'Insert pictures here...'**
  String get insertPicturesHere;

  /// No description provided for @item1.
  ///
  /// In en, this message translates to:
  /// **'Item 1'**
  String get item1;

  /// No description provided for @item2.
  ///
  /// In en, this message translates to:
  /// **'Item 2'**
  String get item2;

  /// No description provided for @item3.
  ///
  /// In en, this message translates to:
  /// **'Item 3'**
  String get item3;

  /// No description provided for @item4.
  ///
  /// In en, this message translates to:
  /// **'Item 4'**
  String get item4;

  /// No description provided for @item5.
  ///
  /// In en, this message translates to:
  /// **'Item 5'**
  String get item5;

  /// No description provided for @noPicturesAdded.
  ///
  /// In en, this message translates to:
  /// **'No pictures added'**
  String get noPicturesAdded;

  /// No description provided for @k1PictureAttached.
  ///
  /// In en, this message translates to:
  /// **'1 picture attached'**
  String get k1PictureAttached;

  /// No description provided for @k2PicturesAttached.
  ///
  /// In en, this message translates to:
  /// **'2 pictures attached'**
  String get k2PicturesAttached;

  /// No description provided for @k3PicturesAttached.
  ///
  /// In en, this message translates to:
  /// **'3 pictures attached'**
  String get k3PicturesAttached;

  /// No description provided for @eventDone.
  ///
  /// In en, this message translates to:
  /// **'Event Done'**
  String get eventDone;

  /// No description provided for @busy.
  ///
  /// In en, this message translates to:
  /// **'Busy'**
  String get busy;

  /// No description provided for @pleaseSelectADate.
  ///
  /// In en, this message translates to:
  /// **'Please select a date'**
  String get pleaseSelectADate;

  /// No description provided for @pleaseSelectAStartTime.
  ///
  /// In en, this message translates to:
  /// **'Please select a start time'**
  String get pleaseSelectAStartTime;

  /// No description provided for @pleaseSelectAnEndTime.
  ///
  /// In en, this message translates to:
  /// **'Please select an end time'**
  String get pleaseSelectAnEndTime;

  /// No description provided for @mustBeAfterStartTime.
  ///
  /// In en, this message translates to:
  /// **'Must be after start time'**
  String get mustBeAfterStartTime;

  /// No description provided for @pleaseSelectAClient.
  ///
  /// In en, this message translates to:
  /// **'Please select a client'**
  String get pleaseSelectAClient;

  /// No description provided for @selectEmployees.
  ///
  /// In en, this message translates to:
  /// **'Select employees'**
  String get selectEmployees;

  /// No description provided for @somethingWentWrongCreatingTheAppointment.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong creating the appointment'**
  String get somethingWentWrongCreatingTheAppointment;

  /// No description provided for @somethingWentWrongSavingChanges.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong saving changes'**
  String get somethingWentWrongSavingChanges;

  /// No description provided for @noEmployeesAssigned.
  ///
  /// In en, this message translates to:
  /// **'No employees assigned'**
  String get noEmployeesAssigned;

  /// No description provided for @addMore.
  ///
  /// In en, this message translates to:
  /// **'Add more'**
  String get addMore;

  /// No description provided for @tapToAddPhotos.
  ///
  /// In en, this message translates to:
  /// **'Tap to add photos'**
  String get tapToAddPhotos;

  /// No description provided for @noPhotos.
  ///
  /// In en, this message translates to:
  /// **'No photos'**
  String get noPhotos;

  /// No description provided for @noNumber.
  ///
  /// In en, this message translates to:
  /// **'No number'**
  String get noNumber;

  /// No description provided for @noAddress.
  ///
  /// In en, this message translates to:
  /// **'No address'**
  String get noAddress;

  /// No description provided for @noNotes.
  ///
  /// In en, this message translates to:
  /// **'No notes'**
  String get noNotes;

  /// No description provided for @noMaterials.
  ///
  /// In en, this message translates to:
  /// **'No materials'**
  String get noMaterials;

  /// No description provided for @markAsDone.
  ///
  /// In en, this message translates to:
  /// **'Mark as done'**
  String get markAsDone;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @appointmentUpdated.
  ///
  /// In en, this message translates to:
  /// **'Appointment updated'**
  String get appointmentUpdated;

  /// No description provided for @deleteJob.
  ///
  /// In en, this message translates to:
  /// **'Delete job'**
  String get deleteJob;

  /// No description provided for @areYouSureYouWantToDeleteThisJob.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this job?'**
  String get areYouSureYouWantToDeleteThisJob;

  /// No description provided for @noEvents.
  ///
  /// In en, this message translates to:
  /// **'No events'**
  String get noEvents;

  /// No description provided for @tapTheButtonToAddOneLater.
  ///
  /// In en, this message translates to:
  /// **'Tap the + button to add one later.'**
  String get tapTheButtonToAddOneLater;

  /// No description provided for @adminName.
  ///
  /// In en, this message translates to:
  /// **'(Admin Name)'**
  String get adminName;

  /// No description provided for @january.
  ///
  /// In en, this message translates to:
  /// **'January'**
  String get january;

  /// No description provided for @february.
  ///
  /// In en, this message translates to:
  /// **'February'**
  String get february;

  /// No description provided for @march.
  ///
  /// In en, this message translates to:
  /// **'March'**
  String get march;

  /// No description provided for @april.
  ///
  /// In en, this message translates to:
  /// **'April'**
  String get april;

  /// No description provided for @may.
  ///
  /// In en, this message translates to:
  /// **'May'**
  String get may;

  /// No description provided for @june.
  ///
  /// In en, this message translates to:
  /// **'June'**
  String get june;

  /// No description provided for @july.
  ///
  /// In en, this message translates to:
  /// **'July'**
  String get july;

  /// No description provided for @august.
  ///
  /// In en, this message translates to:
  /// **'August'**
  String get august;

  /// No description provided for @september.
  ///
  /// In en, this message translates to:
  /// **'September'**
  String get september;

  /// No description provided for @october.
  ///
  /// In en, this message translates to:
  /// **'October'**
  String get october;

  /// No description provided for @november.
  ///
  /// In en, this message translates to:
  /// **'November'**
  String get november;

  /// No description provided for @december.
  ///
  /// In en, this message translates to:
  /// **'December'**
  String get december;

  /// No description provided for @sun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get sun;

  /// No description provided for @mon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get mon;

  /// No description provided for @tue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get tue;

  /// No description provided for @wed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get wed;

  /// No description provided for @thu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get thu;

  /// No description provided for @fri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get fri;

  /// No description provided for @sat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get sat;

  /// No description provided for @generalAppointmentNotes.
  ///
  /// In en, this message translates to:
  /// **'General appointment notes'**
  String get generalAppointmentNotes;

  /// No description provided for @standardTools.
  ///
  /// In en, this message translates to:
  /// **'Standard tools'**
  String get standardTools;

  /// No description provided for @customerRequestedConfirmationCall.
  ///
  /// In en, this message translates to:
  /// **'Customer requested confirmation call'**
  String get customerRequestedConfirmationCall;

  /// No description provided for @replacementParts.
  ///
  /// In en, this message translates to:
  /// **'Replacement parts'**
  String get replacementParts;

  /// No description provided for @accessThroughSideEntrance.
  ///
  /// In en, this message translates to:
  /// **'Access through side entrance'**
  String get accessThroughSideEntrance;

  /// No description provided for @inspectionChecklist.
  ///
  /// In en, this message translates to:
  /// **'Inspection checklist'**
  String get inspectionChecklist;

  /// No description provided for @callOnArrival.
  ///
  /// In en, this message translates to:
  /// **'Call on arrival'**
  String get callOnArrival;

  /// No description provided for @cleaningSupplies.
  ///
  /// In en, this message translates to:
  /// **'Cleaning supplies'**
  String get cleaningSupplies;

  /// No description provided for @bringExtraMaterials.
  ///
  /// In en, this message translates to:
  /// **'Bring extra materials'**
  String get bringExtraMaterials;

  /// No description provided for @extraFittings.
  ///
  /// In en, this message translates to:
  /// **'Extra fittings'**
  String get extraFittings;

  /// No description provided for @changeEmail.
  ///
  /// In en, this message translates to:
  /// **'Change Email'**
  String get changeEmail;

  /// No description provided for @openAddressWith.
  ///
  /// In en, this message translates to:
  /// **'Open address with'**
  String get openAddressWith;

  /// No description provided for @appleMaps.
  ///
  /// In en, this message translates to:
  /// **'Apple Maps'**
  String get appleMaps;

  /// No description provided for @googleMaps.
  ///
  /// In en, this message translates to:
  /// **'Google Maps'**
  String get googleMaps;

  /// No description provided for @waze.
  ///
  /// In en, this message translates to:
  /// **'Waze'**
  String get waze;

  /// No description provided for @couldNotOpenMapApp.
  ///
  /// In en, this message translates to:
  /// **'Could not open map app'**
  String get couldNotOpenMapApp;

  /// No description provided for @adminOnly.
  ///
  /// In en, this message translates to:
  /// **'Admin only'**
  String get adminOnly;

  /// No description provided for @newEmail.
  ///
  /// In en, this message translates to:
  /// **'New email'**
  String get newEmail;

  /// No description provided for @verificationEmailSentPleaseConfirmTheNewEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Verification email sent. Please confirm the new email address.'**
  String get verificationEmailSentPleaseConfirmTheNewEmailAddress;

  /// No description provided for @pleaseLogInAgainBeforeChangingEmail.
  ///
  /// In en, this message translates to:
  /// **'Please log in again before changing email'**
  String get pleaseLogInAgainBeforeChangingEmail;

  /// No description provided for @emailAlreadyInUse.
  ///
  /// In en, this message translates to:
  /// **'Email already in use'**
  String get emailAlreadyInUse;

  /// No description provided for @invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Invalid email'**
  String get invalidEmail;

  /// No description provided for @errorUpdatingEmail.
  ///
  /// In en, this message translates to:
  /// **'Error updating email'**
  String get errorUpdatingEmail;

  /// No description provided for @noEmployeesFound.
  ///
  /// In en, this message translates to:
  /// **'No employees found'**
  String get noEmployeesFound;

  /// No description provided for @noClientsYet.
  ///
  /// In en, this message translates to:
  /// **'No clients yet'**
  String get noClientsYet;

  /// No description provided for @noClientsMatch.
  ///
  /// In en, this message translates to:
  /// **'No clients match'**
  String get noClientsMatch;

  /// No description provided for @noAppointmentsFound.
  ///
  /// In en, this message translates to:
  /// **'No appointments found'**
  String get noAppointmentsFound;

  /// No description provided for @noAppointmentsMatch.
  ///
  /// In en, this message translates to:
  /// **'No appointments match'**
  String get noAppointmentsMatch;

  /// No description provided for @errorLoadingEmployees.
  ///
  /// In en, this message translates to:
  /// **'Error loading employees'**
  String get errorLoadingEmployees;

  /// No description provided for @searchByNameOrPhone.
  ///
  /// In en, this message translates to:
  /// **'Search by name or phone...'**
  String get searchByNameOrPhone;

  /// No description provided for @searchByClientOrEmployee.
  ///
  /// In en, this message translates to:
  /// **'Search by client or employee...'**
  String get searchByClientOrEmployee;

  /// No description provided for @giveAdminModeAccess.
  ///
  /// In en, this message translates to:
  /// **'Give admin mode access'**
  String get giveAdminModeAccess;

  /// No description provided for @nameAndEmailAreRequired.
  ///
  /// In en, this message translates to:
  /// **'Name and email are required'**
  String get nameAndEmailAreRequired;

  /// No description provided for @employeeDeleted.
  ///
  /// In en, this message translates to:
  /// **'Employee deleted'**
  String get employeeDeleted;

  /// No description provided for @employeeAddedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Employee added successfully'**
  String get employeeAddedSuccessfully;

  /// No description provided for @employeeUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Employee updated successfully'**
  String get employeeUpdatedSuccessfully;

  /// No description provided for @anEmployeeWithThisEmailAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'An employee with this email already exists'**
  String get anEmployeeWithThisEmailAlreadyExists;

  /// No description provided for @couldNotCreateEmployee.
  ///
  /// In en, this message translates to:
  /// **'Could not create employee'**
  String get couldNotCreateEmployee;

  /// No description provided for @deleteEmployee.
  ///
  /// In en, this message translates to:
  /// **'Delete employee'**
  String get deleteEmployee;

  /// No description provided for @areYouSureYouWantToDeleteThisEmployee.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this employee?'**
  String get areYouSureYouWantToDeleteThisEmployee;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPassword;

  /// No description provided for @forgotPassword2.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password'**
  String get forgotPassword2;

  /// No description provided for @forgotYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot your password?'**
  String get forgotYourPassword;

  /// No description provided for @enterYourAccountEmailAndWeLlSendYouALinkToResetYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your account email and we\'ll send you a link to reset your password.'**
  String get enterYourAccountEmailAndWeLlSendYouALinkToResetYourPassword;

  /// No description provided for @sendResetEmail.
  ///
  /// In en, this message translates to:
  /// **'Send Reset Email'**
  String get sendResetEmail;

  /// No description provided for @backToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Back to Sign In'**
  String get backToSignIn;

  /// No description provided for @youExampleCom.
  ///
  /// In en, this message translates to:
  /// **'you@example.com'**
  String get youExampleCom;

  /// No description provided for @checkYourEmail.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get checkYourEmail;

  /// No description provided for @weVeSentAPasswordResetLinkTo.
  ///
  /// In en, this message translates to:
  /// **'We\'ve sent a password reset link to:'**
  String get weVeSentAPasswordResetLinkTo;

  /// No description provided for @pleaseCheckYourEmailThenComeBackToTheAppAndSignInWithYourNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Please check your email, then come back to the app and sign in with your new password.'**
  String get pleaseCheckYourEmailThenComeBackToTheAppAndSignInWithYourNewPassword;

  /// No description provided for @didnTReceiveTheEmailTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t receive the email? Try again'**
  String get didnTReceiveTheEmailTryAgain;

  /// No description provided for @emailIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get emailIsRequired;

  /// No description provided for @enterAValidEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get enterAValidEmailAddress;

  /// No description provided for @noAccountFoundForThisEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'No account found for this email address'**
  String get noAccountFoundForThisEmailAddress;

  /// No description provided for @tooManyAttemptsPleaseTryAgainLater.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please try again later.'**
  String get tooManyAttemptsPleaseTryAgainLater;

  /// No description provided for @networkErrorCheckYourConnectionAndTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Network error. Check your connection and try again.'**
  String get networkErrorCheckYourConnectionAndTryAgain;

  /// No description provided for @couldNotSendResetEmail.
  ///
  /// In en, this message translates to:
  /// **'Could not send reset email'**
  String get couldNotSendResetEmail;

  /// No description provided for @passwordResetEmailSentPleaseCheckYourInbox.
  ///
  /// In en, this message translates to:
  /// **'Password reset email sent. Please check your inbox.'**
  String get passwordResetEmailSentPleaseCheckYourInbox;

  /// No description provided for @checkYourInbox.
  ///
  /// In en, this message translates to:
  /// **'Check your inbox'**
  String get checkYourInbox;

  /// No description provided for @ifAnAccountExistsForThisEmailAPasswordResetLinkHasBeenSent.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for this email, a password reset link has been sent.'**
  String get ifAnAccountExistsForThisEmailAPasswordResetLinkHasBeenSent;

  /// No description provided for @theEmailMayTakeAFewMinutesToArriveRememberToCheckYourSpamFolder.
  ///
  /// In en, this message translates to:
  /// **'The email may take a few minutes to arrive. Remember to check your spam folder.'**
  String get theEmailMayTakeAFewMinutesToArriveRememberToCheckYourSpamFolder;

  /// No description provided for @useADifferentEmail.
  ///
  /// In en, this message translates to:
  /// **'Use a different email'**
  String get useADifferentEmail;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @pleaseEnterYourEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter your email'**
  String get pleaseEnterYourEmail;

  /// No description provided for @pleaseEnterYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password'**
  String get pleaseEnterYourPassword;

  /// No description provided for @pleaseEnterAValidEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get pleaseEnterAValidEmailAddress;

  /// No description provided for @invalidEmailOrPassword.
  ///
  /// In en, this message translates to:
  /// **'Invalid email or password'**
  String get invalidEmailOrPassword;

  /// No description provided for @noAccountFoundWithThisEmail.
  ///
  /// In en, this message translates to:
  /// **'No account found with this email'**
  String get noAccountFoundWithThisEmail;

  /// No description provided for @tooManyAttemptsPleaseTryAgainLater2.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts, please try again later'**
  String get tooManyAttemptsPleaseTryAgainLater2;

  /// No description provided for @somethingWentWrongPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong, please try again'**
  String get somethingWentWrongPleaseTryAgain;

  /// No description provided for @thisAccountHasBeenDisabled.
  ///
  /// In en, this message translates to:
  /// **'This account has been disabled'**
  String get thisAccountHasBeenDisabled;

  /// No description provided for @anAccountWithThisEmailAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists'**
  String get anAccountWithThisEmailAlreadyExists;

  /// No description provided for @passwordIsTooWeakUseAtLeast6Characters.
  ///
  /// In en, this message translates to:
  /// **'Password is too weak. Use at least 6 characters'**
  String get passwordIsTooWeakUseAtLeast6Characters;

  /// No description provided for @signInIsTemporarilyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Sign-in is temporarily unavailable'**
  String get signInIsTemporarilyUnavailable;

  /// No description provided for @thisEmailIsNotAuthorizedToSignUp.
  ///
  /// In en, this message translates to:
  /// **'This email is not authorized to sign up'**
  String get thisEmailIsNotAuthorizedToSignUp;

  /// No description provided for @accountCreatedYouCanNowSignIn.
  ///
  /// In en, this message translates to:
  /// **'Account created. You can now sign in.'**
  String get accountCreatedYouCanNowSignIn;

  /// No description provided for @accountCreated.
  ///
  /// In en, this message translates to:
  /// **'Account created'**
  String get accountCreated;

  /// No description provided for @youCanNowSignInWithThisEmailAndPassword.
  ///
  /// In en, this message translates to:
  /// **'You can now sign in with this email and password.'**
  String get youCanNowSignInWithThisEmailAndPassword;

  /// No description provided for @useTheEmailYourAdminAddedToTheEmployeeList.
  ///
  /// In en, this message translates to:
  /// **'Use the email your admin added to the employee list.'**
  String get useTheEmailYourAdminAddedToTheEmployeeList;

  /// No description provided for @noUserProfileFoundForThisAccount.
  ///
  /// In en, this message translates to:
  /// **'No user profile found for this account'**
  String get noUserProfileFoundForThisAccount;

  /// No description provided for @pleaseLogInAgainAndRetry.
  ///
  /// In en, this message translates to:
  /// **'Please log in again and retry'**
  String get pleaseLogInAgainAndRetry;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @forgotPassword3.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword3;

  /// No description provided for @pleaseConfirmYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your password'**
  String get pleaseConfirmYourPassword;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @tapToChangeColor.
  ///
  /// In en, this message translates to:
  /// **'Tap to change color'**
  String get tapToChangeColor;

  /// No description provided for @enterAValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get enterAValidEmail;

  /// No description provided for @pleaseSelectAtLeastOneEmployee.
  ///
  /// In en, this message translates to:
  /// **'Please select at least one employee'**
  String get pleaseSelectAtLeastOneEmployee;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'optional'**
  String get optional;

  /// No description provided for @noEventsFor.
  ///
  /// In en, this message translates to:
  /// **'No events for'**
  String get noEventsFor;

  /// No description provided for @addressLookupFailed.
  ///
  /// In en, this message translates to:
  /// **'Address lookup failed'**
  String get addressLookupFailed;

  /// No description provided for @couldNotLoadAddressDetails.
  ///
  /// In en, this message translates to:
  /// **'Could not load address details'**
  String get couldNotLoadAddressDetails;

  /// No description provided for @searchAddress.
  ///
  /// In en, this message translates to:
  /// **'Search address'**
  String get searchAddress;

  /// No description provided for @typeToSearchAnAddress.
  ///
  /// In en, this message translates to:
  /// **'Type to search an address'**
  String get typeToSearchAnAddress;

  /// No description provided for @street.
  ///
  /// In en, this message translates to:
  /// **'Street'**
  String get street;

  /// No description provided for @welcomeToSchedulingApp.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Scheduling App'**
  String get welcomeToSchedulingApp;

  /// No description provided for @hopeYouAreEnjoyingYourDay.
  ///
  /// In en, this message translates to:
  /// **'Hope you are enjoying your day!'**
  String get hopeYouAreEnjoyingYourDay;

  /// No description provided for @searchByNameBusinessPhoneEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Search by name, business, phone, email, address...'**
  String get searchByNameBusinessPhoneEmailAddress;

  /// No description provided for @noClientsFound.
  ///
  /// In en, this message translates to:
  /// **'No clients found'**
  String get noClientsFound;

  /// No description provided for @user.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get user;

  /// No description provided for @employeeRoleValue.
  ///
  /// In en, this message translates to:
  /// **'Employee'**
  String get employeeRoleValue;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// No description provided for @signInToYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Sign in to your account'**
  String get signInToYourAccount;

  /// No description provided for @fillInYourDetailsBelow.
  ///
  /// In en, this message translates to:
  /// **'Fill in your details below'**
  String get fillInYourDetailsBelow;

  /// No description provided for @alreadyHaveAnAccountSignIn.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get alreadyHaveAnAccountSignIn;

  /// No description provided for @weLlSendALinkToYourEmail.
  ///
  /// In en, this message translates to:
  /// **'We\'ll send a link to your email.'**
  String get weLlSendALinkToYourEmail;

  /// No description provided for @sendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send Reset Link'**
  String get sendResetLink;

  /// No description provided for @backToSignIn2.
  ///
  /// In en, this message translates to:
  /// **'Back to sign in'**
  String get backToSignIn2;

  /// No description provided for @tapToScheduleAnAppointment.
  ///
  /// In en, this message translates to:
  /// **'Tap + to schedule an appointment.'**
  String get tapToScheduleAnAppointment;

  /// No description provided for @searchClients.
  ///
  /// In en, this message translates to:
  /// **'Search clients…'**
  String get searchClients;

  /// No description provided for @searchEmployees.
  ///
  /// In en, this message translates to:
  /// **'Search employees…'**
  String get searchEmployees;

  /// No description provided for @searchAppointments.
  ///
  /// In en, this message translates to:
  /// **'Search appointments…'**
  String get searchAppointments;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

  /// No description provided for @tapToAddYourFirstClient.
  ///
  /// In en, this message translates to:
  /// **'Tap + to add your first client.'**
  String get tapToAddYourFirstClient;

  /// No description provided for @tryADifferentSearchTerm.
  ///
  /// In en, this message translates to:
  /// **'Try a different search term.'**
  String get tryADifferentSearchTerm;

  /// No description provided for @noEmployeesYet.
  ///
  /// In en, this message translates to:
  /// **'No employees yet'**
  String get noEmployeesYet;

  /// No description provided for @tapToInviteYourFirstEmployee.
  ///
  /// In en, this message translates to:
  /// **'Tap + to invite your first employee.'**
  String get tapToInviteYourFirstEmployee;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @pickAColor.
  ///
  /// In en, this message translates to:
  /// **'Pick a Color'**
  String get pickAColor;

  /// No description provided for @disableEmployee.
  ///
  /// In en, this message translates to:
  /// **'Disable employee'**
  String get disableEmployee;

  /// No description provided for @enableEmployee.
  ///
  /// In en, this message translates to:
  /// **'Enable employee'**
  String get enableEmployee;

  /// No description provided for @newAppointment.
  ///
  /// In en, this message translates to:
  /// **'New Appointment'**
  String get newAppointment;

  /// No description provided for @saveAppointment.
  ///
  /// In en, this message translates to:
  /// **'Save Appointment'**
  String get saveAppointment;

  /// No description provided for @assignEmployee.
  ///
  /// In en, this message translates to:
  /// **'Assign Employee'**
  String get assignEmployee;

  /// No description provided for @serviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Service / Title'**
  String get serviceTitle;

  /// No description provided for @changeAddress.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get changeAddress;

  /// No description provided for @clientSAddress.
  ///
  /// In en, this message translates to:
  /// **'Client\'s address'**
  String get clientSAddress;

  /// No description provided for @useClientsAddress.
  ///
  /// In en, this message translates to:
  /// **'← Use client\'s address'**
  String get useClientsAddress;

  /// No description provided for @editAppointment.
  ///
  /// In en, this message translates to:
  /// **'Edit Appointment'**
  String get editAppointment;

  /// No description provided for @deleteAppointment.
  ///
  /// In en, this message translates to:
  /// **'Delete Appointment'**
  String get deleteAppointment;

  /// No description provided for @cancelAppointment.
  ///
  /// In en, this message translates to:
  /// **'Cancel Appointment'**
  String get cancelAppointment;

  /// No description provided for @cancelledJobsAreSavedToHistory.
  ///
  /// In en, this message translates to:
  /// **'Cancelled jobs are saved to history.'**
  String get cancelledJobsAreSavedToHistory;

  /// No description provided for @appointmentStatus.
  ///
  /// In en, this message translates to:
  /// **'Appointment Status'**
  String get appointmentStatus;

  /// No description provided for @assignedEmployee.
  ///
  /// In en, this message translates to:
  /// **'Assigned Employee'**
  String get assignedEmployee;

  /// No description provided for @saveClient.
  ///
  /// In en, this message translates to:
  /// **'Save Client'**
  String get saveClient;

  /// No description provided for @inviteEmployee.
  ///
  /// In en, this message translates to:
  /// **'Invite Employee'**
  String get inviteEmployee;

  /// No description provided for @sendInvite.
  ///
  /// In en, this message translates to:
  /// **'Send Invite'**
  String get sendInvite;

  /// No description provided for @permissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissions;

  /// No description provided for @adminAccess.
  ///
  /// In en, this message translates to:
  /// **'Admin access'**
  String get adminAccess;

  /// No description provided for @adminAccessDescription.
  ///
  /// In en, this message translates to:
  /// **'Can manage all appointments, clients & employees'**
  String get adminAccessDescription;

  /// No description provided for @accountStatus.
  ///
  /// In en, this message translates to:
  /// **'Account Status'**
  String get accountStatus;

  /// No description provided for @accountStatusDescription.
  ///
  /// In en, this message translates to:
  /// **'Controls access & job assignment'**
  String get accountStatusDescription;

  /// No description provided for @disableAccount.
  ///
  /// In en, this message translates to:
  /// **'Disable Account'**
  String get disableAccount;

  /// No description provided for @reEnableAccount.
  ///
  /// In en, this message translates to:
  /// **'Re-enable Account'**
  String get reEnableAccount;

  /// No description provided for @disableAccountNote.
  ///
  /// In en, this message translates to:
  /// **'Disabling removes them from new job assignments. Their past appointments and data are kept.'**
  String get disableAccountNote;

  /// No description provided for @reEnableAccountNote.
  ///
  /// In en, this message translates to:
  /// **'Re-enabling restores their access and allows them to be assigned to jobs again.'**
  String get reEnableAccountNote;

  /// No description provided for @colorAlreadyUsed.
  ///
  /// In en, this message translates to:
  /// **'This color is already used by another employee.'**
  String get colorAlreadyUsed;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'fr': return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
