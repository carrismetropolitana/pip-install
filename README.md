# **PIP KIOSK DEPLOYMENT GUIDE**

This package is the standard deployment utility for Carris Metropolitana's interior (PIPs). It prepares the Linux machine (Raspberry Pi/Ubuntu) for continuous operation by installing the necessary software, forcing full-screen display of the main webpage, and activating the self-healing service. The only configuration required during installation is the machine's unique PIP ID.

## **1\. System Overview and Roles**

The system consists of four files, each with a specific and distinct function in the deployment and runtime cycle.

| File Name | Function | When It Runs | Key Responsibility |
| :---- | :---- | :---- | :---- |
| **install\_pip.sh** | **Installer** | **Manually, Once.** | Installs dependencies, configures the service, and sets the unique **PIP ID** in the config file. |
| **pip.conf** | **Configuration** | On Install & On Every Kiosk Start. | Stores the **Target URL**, PIP\_ID, and **Monitoring/Heartbeat URL**. |
| **pip-kiosk.service** | **System Watchdog** | **Automatically on Boot.** | Tells the Linux OS (systemd) to manage and monitor the Kiosk Manager script, ensuring it always restarts if stopped. |
| **kiosk-manager.sh** | **Runtime Logic** | Continuously by the Service. | Disables screen saving, launches Chromium in fullscreen Kiosk mode, runs the monitoring heartbeat, and forces restarts every 6 hours. |

## **2\. Kiosk Features (Automatic)**

Once the installer is run, the kiosk manages the following features automatically:

* **Autostart:** Launches immediately when the machine boots up.  
* **System Maintenance:**  The entire Raspberry Pi system is scheduled to reboot every 6 hours via a Cron job to ensure a clean environment and prevent memory leaks.
* **Browser Refresh:** Even if the browser is running normally, a forced refresh every 20 minutes ensures that content stays up-to-date and stale pages are avoided.
* **Display Management:** Disables screen savers, power management (DPMS), and hides the mouse cursor.  
* **Monitoring:** Periodically sends a heartbeat to a central monitoring URL with the PIP ID to track uptime and connectivity.

## **3\. Installation Instructions**

### **A. Preparation**

1. Create a directory for installation files and navigate to it:

   ```
   mkdir -p ~/pip-install
   cd ~/pip-install
   ```

2. Download the latest production branch from GitHub:
   ```
   curl -L -o pip-install.zip https://github.com/carrismetropolitana/pip-install/archive/refs/heads/production.zip
   ```

3. Extract the contents:
   ```
   unzip pip-install.zip
   mv pip-install-production/* .
   rm -rf pip-install.zip pip-install-production
   ```

4. Make the installer executable:
   ```
   chmod +x install_pip.sh
   ```

### **B. Execution**

Run the installer with elevated permissions (sudo). The script will guide you through the process, showing clean [OK\] or [FAILED\] status messages.
   ``` 
   sudo ./install\_pip.sh
   ``` 

**Note:** The script will pause and ask you to enter the **unique PIP ID** for this machine. You can **re-run this script at any time** if you need to update the PIP ID.

### **C. Verification**

1. The installer will automatically start the service upon completion.  
2. Check the service status:  
   ```
   systemctl status pip-kiosk
   ```

### **D. Uninstallation (Optional)**

If you ever need to completely remove the kiosk setup, run the uninstall script:

   ``` 
   sudo ./uninstall_pip.sh
   ``` 

This will:

- Stop and disable the systemd service
- Remove all installed scripts and configuration files
- Clear associated cron jobs
- Kill any running Chromium processes

After uninstalling, you can safely re-run install_pip.sh to redeploy the kiosk with the same or a new PIP ID.