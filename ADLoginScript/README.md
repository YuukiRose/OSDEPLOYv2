# ADLoginScript

## Overview
ADLoginScript is a PowerShell-based project designed to facilitate Active Directory login and drive mapping, along with a user-friendly GUI for selecting operating system images. The project is modular, consisting of several PowerShell modules that handle specific functionalities.

## Project Structure
```
ADLoginScript
├── Modules
│   ├── ADLogin.psm1        # Handles Active Directory login functionality
│   ├── PSDriveMapping.psm1 # Responsible for mapping PSDrives
│   └── GUIModule.psm1     # Creates the GUI for user interaction
├── Scripts
│   └── MainScript.ps1      # Orchestrates the execution of the modules
├── LinuxImages
│   ├── Image1              # Contains files related to the first Linux image
│   ├── Image2              # Contains files related to the second Linux image
│   └── Image3              # Contains files related to the third Linux image
├── README.md               # Documentation for the project
└── LICENSE                 # Licensing information for the project
```

## Modules
- **ADLogin.psm1**: This module exports the `Test-ADCredentials` function, which takes a username and password, attempts to create a persistent PSDrive, and returns a boolean indicating success or failure.
  
- **PSDriveMapping.psm1**: This module exports the `Map-PSDrive` function, which maps specified drives and handles any errors that may occur during the process.

- **GUIModule.psm1**: This module exports the `Show-OSSelectionGUI` function, which presents the user with options for selecting the base OS (Windows or Linux) and dynamically generates additional menus based on the user's selections.

## Scripts
- **MainScript.ps1**: The main script that imports the necessary modules, prompts for Active Directory credentials, tests them, maps the drives, and launches the GUI for OS selection.

## Usage
1. Clone the repository to your local machine.
2. Open PowerShell and navigate to the project directory.
3. Run `.\Scripts\MainScript.ps1` to start the application.
4. Follow the prompts to enter your Active Directory credentials and select the desired operating system.

## License
This project is licensed under the terms specified in the LICENSE file.