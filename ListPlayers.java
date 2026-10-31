import java.sql.*;
import java.util.*;

/** Lists every account on a Project Zomboid server with its access level (read-only). */
public class ListPlayers {
    public static void main(String[] args) throws Exception {
        String db = args.length > 0 ? args[0]
                : System.getProperty("user.home") + "\\Zomboid\\db\\bolsonaro_gameplays.db";
        if (!new java.io.File(db).isFile()) {
            System.out.println("Server account database not found: " + db);
            System.exit(1);
        }
        Class.forName("org.sqlite.JDBC");
        Properties p = new Properties();
        p.setProperty("open_mode", "1");          // SQLITE_OPEN_READONLY - never changes the file
        p.setProperty("busy_timeout", "5000");
        try (Connection c = DriverManager.getConnection("jdbc:sqlite:" + db, p)) {
            Set<String> cols = new HashSet<>();
            try (ResultSet r = c.createStatement().executeQuery("PRAGMA table_info(whitelist)")) {
                while (r.next()) cols.add(r.getString("name").toLowerCase());
            }
            String level;
            String join = "";
            if (cols.contains("role")) {
                level = "COALESCE(r.name, CAST(w.role AS TEXT))";
                join = " LEFT JOIN role r ON r.id = w.role";
            } else if (cols.contains("accesslevel")) {
                level = "COALESCE(NULLIF(w.accesslevel,''), 'user')";
            } else {
                level = "'?'";
            }
            String last = cols.contains("lastconnection") ? "COALESCE(w.lastConnection, '-')" : "'-'";
            String sql = "SELECT w.username, " + level + " AS lvl, " + last + " AS last FROM whitelist w" + join
                    + " ORDER BY (" + level + ") IN ('user','none'), w.username COLLATE NOCASE";
            System.out.println();
            System.out.printf("  %-30s %-12s %s%n", "USER", "ACCESS", "LAST LOGIN");
            System.out.printf("  %-30s %-12s %s%n", "----", "------", "----------");
            int n = 0;
            try (ResultSet r = c.createStatement().executeQuery(sql)) {
                while (r.next()) {
                    String lvl = r.getString(2);
                    String mark = ("user".equalsIgnoreCase(lvl) || "none".equalsIgnoreCase(lvl)) ? "" : "  <--";
                    System.out.printf("  %-30s %-12s %s%s%n", r.getString(1), lvl, r.getString(3), mark);
                    n++;
                }
            }
            System.out.println();
            System.out.println("  " + n + " account(s). Change a level in the server console with:");
            System.out.println("    setaccesslevel \"name\" admin     (or moderator, overseer, gm, observer, none)");
        }
    }
}
