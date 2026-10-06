-- Run by the setup account, in one transaction. Existing application rows survive.
CREATE SCHEMA IF NOT EXISTS red_flowers;
REVOKE ALL ON SCHEMA red_flowers FROM PUBLIC;

CREATE TABLE IF NOT EXISTS red_flowers.schema_versions (
    version integer PRIMARY KEY,
    installed_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS red_flowers.families (
    id uuid PRIMARY KEY,
    name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 80),
    login_role name NOT NULL UNIQUE,
    selected_child_id text,
    revision bigint NOT NULL DEFAULT 0 CHECK (revision >= 0),
    created_at timestamptz NOT NULL DEFAULT now()
);
-- Optional UI suggestions become family settings. Older clients ignore the new
-- snapshot fields; existing families receive the new defaults only once.
ALTER TABLE red_flowers.families ADD COLUMN IF NOT EXISTS reward_reasons jsonb
    NOT NULL DEFAULT '["英语打卡", "单词打卡", "体育打卡", "早睡早起"]'::jsonb;
ALTER TABLE red_flowers.families ADD COLUMN IF NOT EXISTS wish_suggestions jsonb
    NOT NULL DEFAULT '[{"title":"看10分钟喜欢的动画","amount":5}]'::jsonb;
CREATE TABLE IF NOT EXISTS red_flowers.children (
    family_id uuid NOT NULL REFERENCES red_flowers.families(id) ON DELETE CASCADE,
    id text NOT NULL CHECK (id ~ '^[A-Za-z0-9_-]{1,128}$'),
    position bigint GENERATED ALWAYS AS IDENTITY,
    name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 12),
    avatar integer NOT NULL CHECK (avatar BETWEEN 0 AND 5),
    balance integer NOT NULL CHECK (balance BETWEEN 0 AND 999999),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (family_id, id)
);
CREATE TABLE IF NOT EXISTS red_flowers.flower_entries (
    family_id uuid NOT NULL,
    id text NOT NULL CHECK (id ~ '^[A-Za-z0-9_-]{1,128}$'),
    child_id text NOT NULL,
    sequence bigint GENERATED ALWAYS AS IDENTITY,
    kind text NOT NULL CHECK (kind IN ('initial', 'reward', 'exchange', 'adjustment')),
    amount integer NOT NULL CHECK (amount BETWEEN -999999 AND 999999),
    reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 1 AND 80),
    balance_after integer NOT NULL CHECK (balance_after BETWEEN 0 AND 999999),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (family_id, id),
    FOREIGN KEY (family_id, child_id) REFERENCES red_flowers.children(family_id, id) ON DELETE CASCADE,
    CHECK ((kind = 'reward' AND amount > 0)
        OR (kind = 'exchange' AND amount < 0)
        OR (kind = 'initial' AND amount >= 0)
        OR kind = 'adjustment')
);
CREATE INDEX IF NOT EXISTS entries_by_child
    ON red_flowers.flower_entries(family_id, child_id, sequence);
CREATE TABLE IF NOT EXISTS red_flowers.commands (
    family_id uuid NOT NULL REFERENCES red_flowers.families(id) ON DELETE CASCADE,
    id uuid NOT NULL,
    kind text NOT NULL,
    payload jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (family_id, id)
);
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
        WHERE conrelid = 'red_flowers.families'::regclass AND conname = 'selected_child_in_family') THEN
        ALTER TABLE red_flowers.families ADD CONSTRAINT selected_child_in_family
            FOREIGN KEY (id, selected_child_id) REFERENCES red_flowers.children(family_id, id)
            DEFERRABLE INITIALLY DEFERRED;
    END IF;
END $$;

-- Private helpers. The app role is granted only get_garden() and apply_command().
CREATE OR REPLACE FUNCTION red_flowers._family() RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, red_flowers AS $$
DECLARE result uuid;
BEGIN
    SELECT id INTO result FROM red_flowers.families WHERE login_role = session_user;
    IF result IS NULL THEN
        RAISE EXCEPTION 'RF:这个账号还没有关联家庭，请检查同步配置' USING ERRCODE = '42501';
    END IF;
    RETURN result;
END $$;
CREATE OR REPLACE FUNCTION red_flowers._text(obj jsonb, field text, max_length integer)
RETURNS text LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE result text;
BEGIN
    IF jsonb_typeof(obj->field) IS DISTINCT FROM 'string' THEN
        RAISE EXCEPTION 'RF:填写的信息不完整' USING ERRCODE = '22023';
    END IF;
    result := btrim(obj->>field, E' \t\n\r');
    IF length(result) NOT BETWEEN 1 AND max_length THEN
        RAISE EXCEPTION 'RF:填写的信息长度不正确' USING ERRCODE = '22023';
    END IF;
    RETURN result;
END $$;
CREATE OR REPLACE FUNCTION red_flowers._int(obj jsonb, field text, low integer, high integer)
RETURNS integer LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE value numeric;
BEGIN
    IF jsonb_typeof(obj->field) IS DISTINCT FROM 'number'
        OR (obj->>field) !~ '^-?[0-9]+$' THEN
        RAISE EXCEPTION 'RF:小红花数量和头像编号必须是整数' USING ERRCODE = '22023';
    END IF;
    value := (obj->>field)::numeric;
    IF value NOT BETWEEN low AND high THEN
        RAISE EXCEPTION 'RF:填写的数量超出允许范围' USING ERRCODE = '22023';
    END IF;
    RETURN value::integer;
END $$;
CREATE OR REPLACE FUNCTION red_flowers._snapshot(family uuid) RETURNS jsonb
LANGUAGE sql SET search_path = pg_catalog, red_flowers AS $$
    SELECT jsonb_build_object(
        'familyId', f.id, 'revision', f.revision, 'serverTime', clock_timestamp(),
        'garden', jsonb_build_object(
            'version', 1, 'selectedChildId', f.selected_child_id,
            'rewardReasons', f.reward_reasons, 'wishSuggestions', f.wish_suggestions,
            'children', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'id', c.id, 'name', c.name, 'avatar', c.avatar, 'balance', c.balance,
                'createdAt', c.created_at) ORDER BY c.position)
                FROM red_flowers.children c WHERE c.family_id = family), '[]'::jsonb),
            'entries', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'id', e.id, 'childId', e.child_id, 'kind', e.kind, 'amount', e.amount,
                'reason', e.reason, 'balanceAfter', e.balance_after, 'createdAt', e.created_at)
                ORDER BY e.sequence)
                FROM red_flowers.flower_entries e WHERE e.family_id = family), '[]'::jsonb)))
    FROM red_flowers.families f WHERE f.id = family
$$;
CREATE OR REPLACE FUNCTION red_flowers.get_garden() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, red_flowers AS $$
DECLARE family uuid := red_flowers._family();
BEGIN
    -- The shared lock makes the profile, selected child, and ledger a consistent snapshot.
    PERFORM 1 FROM red_flowers.families WHERE id = family FOR SHARE;
    RETURN red_flowers._snapshot(family);
END $$;

CREATE OR REPLACE FUNCTION red_flowers._import_local(family uuid, garden jsonb) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog, red_flowers AS $$
DECLARE
    child jsonb; entry jsonb; old_entry red_flowers.flower_entries%ROWTYPE;
    local_child_id text; entry_id text; entry_kind text; amount integer; running_balance integer;
    imported_ids text[] := ARRAY[]::text[]; selected text;
BEGIN
    IF garden->>'version' IS DISTINCT FROM '1'
        OR jsonb_typeof(garden->'children') IS DISTINCT FROM 'array'
        OR jsonb_typeof(garden->'entries') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'RF:本地数据格式不正确，原数据已保留' USING ERRCODE = '22023';
    END IF;
    IF (SELECT count(*) FROM jsonb_array_elements(garden->'entries')) <>
        (SELECT count(DISTINCT e->>'id') FROM jsonb_array_elements(garden->'entries') e) THEN
        RAISE EXCEPTION 'RF:本地记录编号重复，原数据已保留' USING ERRCODE = '22023';
    END IF;
    -- Existing profiles are never overwritten by an older local snapshot.
    FOR child IN SELECT value FROM jsonb_array_elements(garden->'children') LOOP
        local_child_id := red_flowers._text(child, 'id', 128);
        IF local_child_id = ANY(imported_ids) THEN
            RAISE EXCEPTION 'RF:本地小朋友编号重复，原数据已保留' USING ERRCODE = '22023';
        END IF;
        imported_ids := array_append(imported_ids, local_child_id);
        PERFORM red_flowers._text(child, 'name', 12);
        PERFORM red_flowers._int(child, 'avatar', 0, 5);
        PERFORM red_flowers._int(child, 'balance', 0, 999999);
        IF NOT EXISTS (SELECT 1 FROM red_flowers.children c
            WHERE c.family_id = family AND c.id = local_child_id) THEN
            INSERT INTO red_flowers.children(family_id, id, name, avatar, balance, created_at)
                VALUES (family, local_child_id, red_flowers._text(child, 'name', 12),
                    red_flowers._int(child, 'avatar', 0, 5), 0,
                    (red_flowers._text(child, 'createdAt', 80))::timestamptz);
        END IF;
    END LOOP;
    -- Walk each child's local ledger independently, in its original order.
    FOR child IN SELECT value FROM jsonb_array_elements(garden->'children') LOOP
        local_child_id := child->>'id'; running_balance := 0;
        FOR entry IN SELECT value FROM jsonb_array_elements(garden->'entries')
            WHERE value->>'childId' = local_child_id LOOP
            entry_id := red_flowers._text(entry, 'id', 128);
            entry_kind := red_flowers._text(entry, 'kind', 16);
            amount := red_flowers._int(entry, 'amount', -999999, 999999);
            IF entry_kind NOT IN ('initial', 'reward', 'exchange', 'adjustment')
                OR (entry_kind = 'reward' AND amount <= 0)
                OR (entry_kind = 'exchange' AND amount >= 0)
                OR (entry_kind = 'initial' AND amount < 0) THEN
                RAISE EXCEPTION 'RF:本地记录类型不正确，原数据已保留' USING ERRCODE = '22023';
            END IF;
            running_balance := running_balance + amount;
            IF running_balance NOT BETWEEN 0 AND 999999
                OR running_balance <> red_flowers._int(entry, 'balanceAfter', 0, 999999) THEN
                RAISE EXCEPTION 'RF:本地花数与记录不一致，原数据已保留' USING ERRCODE = '22023';
            END IF;
            SELECT * INTO old_entry FROM red_flowers.flower_entries e
                WHERE e.family_id = family AND e.id = entry_id;
            IF FOUND THEN
                IF old_entry.child_id <> local_child_id OR old_entry.kind <> entry_kind
                    OR old_entry.amount <> amount
                    OR old_entry.reason <> red_flowers._text(entry, 'reason', 80)
                    OR old_entry.balance_after <> running_balance
                    OR old_entry.created_at <> (red_flowers._text(entry, 'createdAt', 80))::timestamptz THEN
                    RAISE EXCEPTION 'RF:本地和云端记录存在差异，原数据已保留' USING ERRCODE = '40001';
                END IF;
            ELSE
                -- A complete new local child can be imported, but an overlapping,
                -- diverged ledger must not silently rewrite any cloud history.
                IF EXISTS (SELECT 1 FROM red_flowers.commands cmd WHERE cmd.family_id = family
                    AND cmd.payload->>'childId' = local_child_id)
                    OR EXISTS (SELECT 1 FROM red_flowers.flower_entries e
                        WHERE e.family_id = family AND e.child_id = local_child_id
                            AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(garden->'entries') local_entry
                                WHERE local_entry->>'id' = e.id)) THEN
                    RAISE EXCEPTION 'RF:本地和云端记录存在差异，请先保留本地备份' USING ERRCODE = '40001';
                END IF;
                INSERT INTO red_flowers.flower_entries
                    (family_id, id, child_id, kind, amount, reason, balance_after, created_at)
                    VALUES (family, entry_id, local_child_id, entry_kind, amount,
                        red_flowers._text(entry, 'reason', 80), running_balance,
                        (red_flowers._text(entry, 'createdAt', 80))::timestamptz);
                UPDATE red_flowers.children SET balance = running_balance
                    WHERE family_id = family AND id = local_child_id;
            END IF;
        END LOOP;
        IF running_balance <> red_flowers._int(child, 'balance', 0, 999999) THEN
            RAISE EXCEPTION 'RF:本地余额不正确，原数据已保留' USING ERRCODE = '22023';
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(garden->'entries') e
        WHERE NOT ((e->>'childId') = ANY(imported_ids))) THEN
        RAISE EXCEPTION 'RF:本地记录关联的小朋友不存在' USING ERRCODE = '22023';
    END IF;
    selected := garden->>'selectedChildId';
    IF (cardinality(imported_ids) > 0 AND (selected IS NULL OR NOT selected = ANY(imported_ids)))
        OR (cardinality(imported_ids) = 0 AND selected IS NOT NULL) THEN
        RAISE EXCEPTION 'RF:本地小朋友选择不完整' USING ERRCODE = '22023';
    END IF;
    UPDATE red_flowers.families SET selected_child_id = COALESCE(selected_child_id, selected)
        WHERE id = family;
END $$;

CREATE OR REPLACE FUNCTION red_flowers.apply_command(command jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, red_flowers AS $$
DECLARE
    family uuid := red_flowers._family(); command_id uuid; command_kind text; payload jsonb;
    previous red_flowers.commands%ROWTYPE; child red_flowers.children%ROWTYPE;
    child_id text; new_name text; new_avatar integer; new_balance integer;
    quantity integer; delta integer; reason text; event_kind text; at_time timestamptz := clock_timestamp();
    suggestions jsonb; normalized jsonb; suggestion jsonb; title text;
BEGIN
    IF jsonb_typeof(command) IS DISTINCT FROM 'object' OR octet_length(command::text) > 4000000 THEN
        RAISE EXCEPTION 'RF:保存的数据格式或大小不正确' USING ERRCODE = '22023';
    END IF;
    command_id := red_flowers._text(command, 'id', 80)::uuid;
    command_kind := red_flowers._text(command, 'kind', 24);
    payload := command->'payload';
    IF jsonb_typeof(payload) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'RF:操作信息不完整' USING ERRCODE = '22023';
    END IF;
    -- Every writer locks the same family row before touching its ledger.
    -- Requests from multiple devices are serialized inside PostgreSQL.
    PERFORM 1 FROM red_flowers.families WHERE id = family FOR UPDATE;
    SELECT * INTO previous FROM red_flowers.commands WHERE family_id = family AND id = command_id;
    IF FOUND THEN
        IF previous.kind <> command_kind OR previous.payload <> payload THEN
            RAISE EXCEPTION 'RF:操作编号已使用，请重新同步' USING ERRCODE = '22023';
        END IF;
        RETURN red_flowers._snapshot(family);
    END IF;
    IF command_kind = 'import_local' THEN
        PERFORM red_flowers._import_local(family, payload->'garden');
    ELSIF command_kind IN ('set_reward_reasons', 'set_wish_suggestions') THEN
        suggestions := CASE WHEN command_kind = 'set_reward_reasons'
            THEN payload->'rewardReasons' ELSE payload->'wishSuggestions' END;
        IF jsonb_typeof(suggestions) IS DISTINCT FROM 'array' THEN
            RAISE EXCEPTION 'RF:候选项格式不正确' USING ERRCODE = '22023';
        END IF;
        IF jsonb_array_length(suggestions) > 20 THEN
            RAISE EXCEPTION 'RF:候选项最多 20 个' USING ERRCODE = '22023';
        END IF;
        normalized := '[]'::jsonb;
        FOR suggestion IN SELECT value FROM jsonb_array_elements(suggestions) LOOP
            IF command_kind = 'set_reward_reasons' THEN
                title := red_flowers._text(jsonb_build_object('title', suggestion), 'title', 80);
                normalized := normalized || jsonb_build_array(title);
            ELSE
                title := red_flowers._text(suggestion, 'title', 80);
                quantity := red_flowers._int(suggestion, 'amount', 1, 999999);
                normalized := normalized || jsonb_build_array(jsonb_build_object('title', title, 'amount', quantity));
            END IF;
        END LOOP;
        IF jsonb_array_length(normalized) <> (SELECT count(DISTINCT CASE
            WHEN command_kind = 'set_reward_reasons' THEN value #>> '{}'
            ELSE value->>'title' END) FROM jsonb_array_elements(normalized)) THEN
            RAISE EXCEPTION 'RF:候选项名称不能重复' USING ERRCODE = '22023';
        END IF;
        IF command_kind = 'set_reward_reasons' THEN
            IF payload->'expectedRewardReasons' IS DISTINCT FROM
                (SELECT reward_reasons FROM red_flowers.families WHERE id = family) THEN
                RAISE EXCEPTION 'RF:努力候选项已在另一台设备更新，请同步后重新打开设置' USING ERRCODE = '40001';
            END IF;
            UPDATE red_flowers.families SET reward_reasons = normalized WHERE id = family;
        ELSE
            IF payload->'expectedWishSuggestions' IS DISTINCT FROM
                (SELECT wish_suggestions FROM red_flowers.families WHERE id = family) THEN
                RAISE EXCEPTION 'RF:心愿灵感已在另一台设备更新，请同步后重新打开设置' USING ERRCODE = '40001';
            END IF;
            UPDATE red_flowers.families SET wish_suggestions = normalized WHERE id = family;
        END IF;
    ELSE
        child_id := red_flowers._text(payload, 'childId', 128);
        IF command_kind = 'add_child' THEN
            new_name := red_flowers._text(payload, 'name', 12);
            new_avatar := red_flowers._int(payload, 'avatar', 0, 5);
            new_balance := red_flowers._int(payload, 'balance', 0, 999999);
            INSERT INTO red_flowers.children(family_id, id, name, avatar, balance, created_at)
                VALUES (family, child_id, new_name, new_avatar, new_balance, at_time);
            INSERT INTO red_flowers.flower_entries
                (family_id, id, child_id, kind, amount, reason, balance_after, created_at)
                VALUES (family, command_id::text, child_id, 'initial', new_balance,
                    '开启小花园 · 初始小红花', new_balance, at_time);
            UPDATE red_flowers.families SET selected_child_id = child_id WHERE id = family;
        ELSE
            SELECT * INTO child FROM red_flowers.children WHERE family_id = family AND id = child_id;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'RF:没有找到这位小朋友，请先同步' USING ERRCODE = '22023';
            END IF;
            IF command_kind = 'select_child' THEN
                UPDATE red_flowers.families SET selected_child_id = child_id WHERE id = family;
            ELSIF command_kind = 'update_child' THEN
                new_name := red_flowers._text(payload, 'name', 12);
                new_avatar := red_flowers._int(payload, 'avatar', 0, 5);
                new_balance := child.balance;
                IF payload->'balance' IS NOT NULL AND payload->'balance' <> 'null'::jsonb THEN
                    IF child.balance <> red_flowers._int(payload, 'expectedBalance', 0, 999999) THEN
                        RAISE EXCEPTION 'RF:花数已在另一台设备更新，请同步后重新设置' USING ERRCODE = '40001';
                    END IF;
                    new_balance := red_flowers._int(payload, 'balance', 0, 999999);
                END IF;
                UPDATE red_flowers.children SET name = new_name, avatar = new_avatar, balance = new_balance
                    WHERE family_id = family AND id = child_id;
                IF new_balance <> child.balance THEN
                    INSERT INTO red_flowers.flower_entries
                        (family_id, id, child_id, kind, amount, reason, balance_after, created_at)
                        VALUES (family, command_id::text, child_id, 'adjustment', new_balance - child.balance,
                            format('家长设置花数：%s → %s', child.balance, new_balance), new_balance, at_time);
                END IF;
            ELSIF command_kind IN ('reward', 'exchange') THEN
                quantity := red_flowers._int(payload, 'amount', 1, 999999);
                reason := red_flowers._text(payload, 'reason', 80);
                delta := CASE WHEN command_kind = 'exchange' THEN -quantity ELSE quantity END;
                new_balance := child.balance + delta;
                IF new_balance < 0 THEN
                    RAISE EXCEPTION 'RF:小红花不够啦，请同步最新花数' USING ERRCODE = 'P0001';
                ELSIF new_balance > 999999 THEN
                    RAISE EXCEPTION 'RF:小红花数量不能超过 999999' USING ERRCODE = 'P0001';
                END IF;
                UPDATE red_flowers.children SET balance = new_balance WHERE family_id = family AND id = child_id;
                INSERT INTO red_flowers.flower_entries
                    (family_id, id, child_id, kind, amount, reason, balance_after, created_at)
                    VALUES (family, command_id::text, child_id, command_kind, delta, reason, new_balance, at_time);
            ELSE
                RAISE EXCEPTION 'RF:不支持这个操作，请更新应用' USING ERRCODE = '22023';
            END IF;
        END IF;
    END IF;
    INSERT INTO red_flowers.commands(family_id, id, kind, payload)
        VALUES (family, command_id, command_kind, payload);
    UPDATE red_flowers.families SET revision = revision + 1 WHERE id = family;
    RETURN red_flowers._snapshot(family);
END $$;

REVOKE ALL ON ALL TABLES IN SCHEMA red_flowers FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA red_flowers FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA red_flowers FROM PUBLIC;
INSERT INTO red_flowers.schema_versions(version) VALUES (1) ON CONFLICT DO NOTHING;
INSERT INTO red_flowers.schema_versions(version) VALUES (2) ON CONFLICT DO NOTHING;
