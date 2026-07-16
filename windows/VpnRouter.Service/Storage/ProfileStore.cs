using System.Text.Json;
using Microsoft.Data.Sqlite;
using VpnRouter.Core.Profiles;
using VpnRouter.Core.Rules;
using VpnRouter.Vpn.WireGuard;

namespace VpnRouter.Service.Storage;

public sealed class ProfileStore
{
    private readonly string _databasePath;

    public ProfileStore()
    {
        var dataDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "VpnRouter");

        Directory.CreateDirectory(dataDirectory);
        _databasePath = Path.Combine(dataDirectory, "vpnrouter.db");
    }

    public async Task InitializeAsync(CancellationToken cancellationToken)
    {
        await using var connection = OpenConnection();
        await ExecuteNonQueryAsync(connection, """
            CREATE TABLE IF NOT EXISTS profiles (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                type INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                enabled INTEGER NOT NULL,
                config_ref TEXT NOT NULL,
                provider_id TEXT NULL
            );
            """, cancellationToken);

        await ExecuteNonQueryAsync(connection, """
            CREATE TABLE IF NOT EXISTS wireguard_configs (
                profile_id TEXT PRIMARY KEY,
                sanitized_config TEXT NOT NULL,
                private_key_ref TEXT NOT NULL,
                summary_json TEXT NOT NULL,
                imported_at TEXT NOT NULL,
                FOREIGN KEY(profile_id) REFERENCES profiles(id)
            );
            """, cancellationToken);

        await ExecuteNonQueryAsync(connection, """
            CREATE TABLE IF NOT EXISTS domain_rules (
                id TEXT PRIMARY KEY,
                profile_id TEXT NOT NULL,
                domain TEXT NOT NULL,
                include_subdomains INTEGER NOT NULL,
                enabled INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY(profile_id) REFERENCES profiles(id)
            );
            """, cancellationToken);
    }

    public async Task SaveWireGuardProfileAsync(
        VpnProfile profile,
        WireGuardImportResult importResult,
        string privateKeyRef,
        CancellationToken cancellationToken)
    {
        await InitializeAsync(cancellationToken);
        await using var connection = OpenConnection();
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        await using (var command = connection.CreateCommand())
        {
            command.Transaction = (SqliteTransaction)transaction;
            command.CommandText = """
                INSERT INTO profiles (id, name, type, created_at, updated_at, enabled, config_ref, provider_id)
                VALUES ($id, $name, $type, $created_at, $updated_at, $enabled, $config_ref, $provider_id)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    type = excluded.type,
                    updated_at = excluded.updated_at,
                    enabled = excluded.enabled,
                    config_ref = excluded.config_ref,
                    provider_id = excluded.provider_id;
                """;

            command.Parameters.AddWithValue("$id", profile.Id.ToString());
            command.Parameters.AddWithValue("$name", profile.Name);
            command.Parameters.AddWithValue("$type", (int)profile.Type);
            command.Parameters.AddWithValue("$created_at", profile.CreatedAt.ToString("O"));
            command.Parameters.AddWithValue("$updated_at", profile.UpdatedAt.ToString("O"));
            command.Parameters.AddWithValue("$enabled", profile.Enabled ? 1 : 0);
            command.Parameters.AddWithValue("$config_ref", profile.ConfigRef);
            command.Parameters.AddWithValue("$provider_id", (object?)profile.ProviderId ?? DBNull.Value);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var command = connection.CreateCommand())
        {
            command.Transaction = (SqliteTransaction)transaction;
            command.CommandText = """
                INSERT INTO wireguard_configs (profile_id, sanitized_config, private_key_ref, summary_json, imported_at)
                VALUES ($profile_id, $sanitized_config, $private_key_ref, $summary_json, $imported_at)
                ON CONFLICT(profile_id) DO UPDATE SET
                    sanitized_config = excluded.sanitized_config,
                    private_key_ref = excluded.private_key_ref,
                    summary_json = excluded.summary_json,
                    imported_at = excluded.imported_at;
                """;

            command.Parameters.AddWithValue("$profile_id", profile.Id.ToString());
            command.Parameters.AddWithValue("$sanitized_config", importResult.SanitizedConfig);
            command.Parameters.AddWithValue("$private_key_ref", privateKeyRef);
            command.Parameters.AddWithValue("$summary_json", JsonSerializer.Serialize(importResult.Summary));
            command.Parameters.AddWithValue("$imported_at", DateTimeOffset.UtcNow.ToString("O"));
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<VpnProfile>> ListProfilesAsync(CancellationToken cancellationToken)
    {
        await InitializeAsync(cancellationToken);
        await using var connection = OpenConnection();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT id, name, type, created_at, updated_at, enabled, config_ref, provider_id
            FROM profiles
            ORDER BY updated_at DESC;
            """;

        var profiles = new List<VpnProfile>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            profiles.Add(new VpnProfile(
                Guid.Parse(reader.GetString(0)),
                reader.GetString(1),
                (VpnProfileType)reader.GetInt32(2),
                reader.GetInt32(5) == 1,
                reader.GetString(6),
                reader.IsDBNull(7) ? null : reader.GetString(7),
                DateTimeOffset.Parse(reader.GetString(3)),
                DateTimeOffset.Parse(reader.GetString(4))));
        }

        return profiles;
    }

    public async Task<IReadOnlyDictionary<Guid, WireGuardConfigSummary>> ListWireGuardSummariesAsync(CancellationToken cancellationToken)
    {
        await InitializeAsync(cancellationToken);
        await using var connection = OpenConnection();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT profile_id, summary_json
            FROM wireguard_configs;
            """;

        var summaries = new Dictionary<Guid, WireGuardConfigSummary>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var profileId = Guid.Parse(reader.GetString(0));
            var summary = JsonSerializer.Deserialize<WireGuardConfigSummary>(reader.GetString(1));
            if (summary is not null)
            {
                summaries[profileId] = summary;
            }
        }

        return summaries;
    }

    public async Task<VpnProfile?> GetProfileAsync(Guid profileId, CancellationToken cancellationToken)
    {
        await InitializeAsync(cancellationToken);
        await using var connection = OpenConnection();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT id, name, type, created_at, updated_at, enabled, config_ref, provider_id
            FROM profiles
            WHERE id = $id;
            """;
        command.Parameters.AddWithValue("$id", profileId.ToString());

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new VpnProfile(
            Guid.Parse(reader.GetString(0)),
            reader.GetString(1),
            (VpnProfileType)reader.GetInt32(2),
            reader.GetInt32(5) == 1,
            reader.GetString(6),
            reader.IsDBNull(7) ? null : reader.GetString(7),
            DateTimeOffset.Parse(reader.GetString(3)),
            DateTimeOffset.Parse(reader.GetString(4)));
    }

    public async Task<(string SanitizedConfig, string PrivateKeyRef)?> GetWireGuardConfigRecordAsync(
        Guid profileId,
        CancellationToken cancellationToken)
    {
        await InitializeAsync(cancellationToken);
        await using var connection = OpenConnection();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT sanitized_config, private_key_ref
            FROM wireguard_configs
            WHERE profile_id = $profile_id;
            """;
        command.Parameters.AddWithValue("$profile_id", profileId.ToString());

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return (reader.GetString(0), reader.GetString(1));
    }

    public async Task SaveDomainRulesAsync(
        Guid profileId,
        IReadOnlyList<DomainRule> rules,
        CancellationToken cancellationToken)
    {
        await InitializeAsync(cancellationToken);
        await using var connection = OpenConnection();
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        await using (var delete = connection.CreateCommand())
        {
            delete.Transaction = (SqliteTransaction)transaction;
            delete.CommandText = "DELETE FROM domain_rules WHERE profile_id = $profile_id;";
            delete.Parameters.AddWithValue("$profile_id", profileId.ToString());
            await delete.ExecuteNonQueryAsync(cancellationToken);
        }

        foreach (var rule in rules)
        {
            await using var insert = connection.CreateCommand();
            insert.Transaction = (SqliteTransaction)transaction;
            insert.CommandText = """
                INSERT INTO domain_rules (id, profile_id, domain, include_subdomains, enabled, created_at)
                VALUES ($id, $profile_id, $domain, $include_subdomains, $enabled, $created_at);
                """;
            insert.Parameters.AddWithValue("$id", rule.Id.ToString());
            insert.Parameters.AddWithValue("$profile_id", profileId.ToString());
            insert.Parameters.AddWithValue("$domain", rule.Domain);
            insert.Parameters.AddWithValue("$include_subdomains", rule.IncludeSubdomains ? 1 : 0);
            insert.Parameters.AddWithValue("$enabled", rule.Enabled ? 1 : 0);
            insert.Parameters.AddWithValue("$created_at", rule.CreatedAt.ToString("O"));
            await insert.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
    }

    public async Task RenameProfileAsync(Guid profileId, string name, CancellationToken cancellationToken)
    {
        await InitializeAsync(cancellationToken);
        await using var connection = OpenConnection();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            UPDATE profiles
            SET name = $name,
                updated_at = $updated_at
            WHERE id = $id;
            """;
        command.Parameters.AddWithValue("$id", profileId.ToString());
        command.Parameters.AddWithValue("$name", name.Trim());
        command.Parameters.AddWithValue("$updated_at", DateTimeOffset.UtcNow.ToString("O"));

        var rows = await command.ExecuteNonQueryAsync(cancellationToken);
        if (rows == 0)
        {
            throw new InvalidOperationException($"Profile not found: {profileId}");
        }
    }

    public async Task<IReadOnlyList<string>> DeleteProfileAsync(Guid profileId, CancellationToken cancellationToken)
    {
        await InitializeAsync(cancellationToken);
        await using var connection = OpenConnection();
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        var secretRefs = new List<string>();
        await using (var selectSecrets = connection.CreateCommand())
        {
            selectSecrets.Transaction = (SqliteTransaction)transaction;
            selectSecrets.CommandText = "SELECT private_key_ref FROM wireguard_configs WHERE profile_id = $profile_id;";
            selectSecrets.Parameters.AddWithValue("$profile_id", profileId.ToString());
            await using var reader = await selectSecrets.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                secretRefs.Add(reader.GetString(0));
            }
        }

        foreach (var commandText in new[]
        {
            "DELETE FROM domain_rules WHERE profile_id = $profile_id;",
            "DELETE FROM wireguard_configs WHERE profile_id = $profile_id;",
            "DELETE FROM profiles WHERE id = $profile_id;"
        })
        {
            await using var command = connection.CreateCommand();
            command.Transaction = (SqliteTransaction)transaction;
            command.CommandText = commandText;
            command.Parameters.AddWithValue("$profile_id", profileId.ToString());
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        return secretRefs;
    }

    public async Task<IReadOnlyList<DomainRule>> ListDomainRulesAsync(
        Guid profileId,
        CancellationToken cancellationToken)
    {
        await InitializeAsync(cancellationToken);
        await using var connection = OpenConnection();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT id, profile_id, domain, include_subdomains, enabled, created_at
            FROM domain_rules
            WHERE profile_id = $profile_id
            ORDER BY created_at ASC;
            """;
        command.Parameters.AddWithValue("$profile_id", profileId.ToString());

        var rules = new List<DomainRule>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            rules.Add(new DomainRule(
                Guid.Parse(reader.GetString(0)),
                Guid.Parse(reader.GetString(1)),
                reader.GetString(2),
                reader.GetInt32(3) == 1,
                reader.GetInt32(4) == 1,
                DateTimeOffset.Parse(reader.GetString(5))));
        }

        return rules;
    }

    private SqliteConnection OpenConnection()
    {
        var connection = new SqliteConnection($"Data Source={_databasePath}");
        connection.Open();
        return connection;
    }

    private static async Task ExecuteNonQueryAsync(
        SqliteConnection connection,
        string commandText,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = commandText;
        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}
