using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Windows.Forms;

namespace CodexKianaPet
{
  internal static class PetEnhancerLauncher
  {
    [STAThread]
    private static int Main(string[] args)
    {
      Application.EnableVisualStyles();
      Application.SetCompatibleTextRenderingDefault(false);
      try
      {
        string scriptPath = null;
        int? port = null;
        for (int index = 0; index < args.Length; index++)
        {
          if (string.Equals(args[index], "--script", StringComparison.OrdinalIgnoreCase) && index + 1 < args.Length)
          {
            scriptPath = args[++index];
            continue;
          }
          if (string.Equals(args[index], "--port", StringComparison.OrdinalIgnoreCase) && index + 1 < args.Length)
          {
            int parsedPort;
            if (!int.TryParse(args[++index], NumberStyles.None, CultureInfo.InvariantCulture, out parsedPort) ||
                parsedPort < 1024 || parsedPort > 65535)
            {
              throw new InvalidOperationException("桌宠启动端口无效。");
            }
            port = parsedPort;
          }
        }
        if (string.IsNullOrWhiteSpace(scriptPath))
        {
          throw new InvalidOperationException("快捷方式缺少桌宠启动脚本路径。");
        }
        scriptPath = Path.GetFullPath(scriptPath);
        if (!File.Exists(scriptPath) ||
            !string.Equals(Path.GetFileName(scriptPath), "start-pet-enhancer.ps1", StringComparison.OrdinalIgnoreCase))
        {
          throw new FileNotFoundException("找不到可信的桌宠启动脚本。", scriptPath);
        }

        string windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        string powershell = Path.Combine(windows, @"System32\WindowsPowerShell\v1.0\powershell.exe");
        if (!File.Exists(powershell)) throw new FileNotFoundException("找不到 Windows PowerShell。", powershell);

        string arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File " + Quote(scriptPath);
        if (port.HasValue) arguments += " -Port " + port.Value.ToString(CultureInfo.InvariantCulture);
        arguments += " -PromptRestart";
        ProcessStartInfo startInfo = new ProcessStartInfo();
        startInfo.FileName = powershell;
        startInfo.Arguments = arguments;
        startInfo.WorkingDirectory = Directory.GetParent(Path.GetDirectoryName(scriptPath)).FullName;
        startInfo.UseShellExecute = false;
        startInfo.CreateNoWindow = true;
        startInfo.WindowStyle = ProcessWindowStyle.Hidden;

        string standardOutput = string.Empty;
        string standardError = string.Empty;
        int exitCode;
        using (Process process = Process.Start(startInfo))
        {
          process.WaitForExit();
          exitCode = process.ExitCode;
        }
        WriteLog(scriptPath, exitCode, standardOutput, standardError);
        if (exitCode != 0)
        {
          ShowError("桌宠启动失败，退出代码：" + exitCode.ToString(CultureInfo.InvariantCulture) +
            "。\r\n\r\n请查看桌宠注入日志和启动器日志：\r\n" + GetLogPath());
        }
        return exitCode;
      }
      catch (Exception exception)
      {
        try { WriteLog(string.Empty, -1, string.Empty, exception.ToString()); } catch { }
        ShowError("桌宠启动器出错。\r\n\r\n" + exception.Message + "\r\n\r\n详细日志：\r\n" + GetLogPath());
        return 1;
      }
    }

    private static string Quote(string value)
    {
      if (value.IndexOf('"') >= 0) throw new InvalidOperationException("启动路径包含不支持的引号字符。");
      return "\"" + value + "\"";
    }

    private static string GetLogPath()
    {
      return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "CodexKianaPet", "launcher.log");
    }

    private static void WriteLog(string scriptPath, int exitCode, string standardOutput, string standardError)
    {
      string logPath = GetLogPath();
      Directory.CreateDirectory(Path.GetDirectoryName(logPath));
      StringBuilder entry = new StringBuilder();
      entry.AppendLine("[" + DateTimeOffset.Now.ToString("O", CultureInfo.InvariantCulture) + "]");
      entry.AppendLine("script=" + scriptPath);
      entry.AppendLine("exitCode=" + exitCode.ToString(CultureInfo.InvariantCulture));
      if (!string.IsNullOrWhiteSpace(standardOutput)) entry.AppendLine("stdout=" + standardOutput.Trim());
      if (!string.IsNullOrWhiteSpace(standardError)) entry.AppendLine("stderr=" + standardError.Trim());
      entry.AppendLine();
      File.AppendAllText(logPath, entry.ToString(), new UTF8Encoding(false));
    }

    private static string TrimForDialog(string value)
    {
      if (string.IsNullOrWhiteSpace(value)) return "未返回具体错误信息。";
      value = value.Trim();
      return value.Length <= 1200 ? value : value.Substring(value.Length - 1200);
    }

    private static void ShowError(string message)
    {
      MessageBox.Show(message, "Codex 琪亚娜桌宠", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }
  }
}
