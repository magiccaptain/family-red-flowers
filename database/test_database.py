import concurrent.futures
import copy
import unittest
from uuid import uuid4

import psycopg

from testing import TemporaryFamily, command


class DatabaseTests(unittest.TestCase):
    def setUp(self):
        self.family = TemporaryFamily().__enter__()
        self.addCleanup(self.family.__exit__)
        self.child = str(uuid4())

    def add(self, balance=10):
        return self.family.apply(command("add_child", childId=self.child,
                                        name="验证小朋友", avatar=1, balance=balance))

    def test_complete_features_and_reload(self):
        self.add(20)
        reward = command("reward", childId=self.child, amount=3, reason="读书")
        self.family.apply(reward)
        self.family.apply(command("exchange", childId=self.child, amount=10, reason="兑换绘本"))
        second = str(uuid4())
        self.family.apply(command("add_child", childId=second, name="第二位", avatar=2, balance=7))
        self.family.apply(command("select_child", childId=self.child))
        self.family.apply(command("update_child", childId=self.child, name="改昵称", avatar=3,
                                  balance=5, expectedBalance=13))
        data = self.family.read()["garden"]
        self.assertEqual(data["selectedChildId"], self.child)
        self.assertEqual([c["balance"] for c in data["children"]], [5, 7])
        entries = [e for e in data["entries"] if e["childId"] == self.child]
        self.assertEqual([e["amount"] for e in entries], [20, 3, -10, -8])
        self.assertEqual(entries[2]["reason"], "兑换绘本")
        self.assertEqual(entries[-1]["balanceAfter"], 5)
        self.assertEqual(data["children"][0]["avatar"], 3)

    def test_family_suggestions_sync_without_changing_history_and_retry_once(self):
        initial = self.family.read()["garden"]
        self.assertEqual(initial["rewardReasons"], ["英语打卡", "单词打卡", "体育打卡", "早睡早起"])
        self.assertEqual(initial["wishSuggestions"], [{"title": "看10分钟喜欢的动画", "amount": 5}])
        reward_call = command("set_reward_reasons", rewardReasons=[" 阅读打卡 ", "运动"],
                              expectedRewardReasons=initial["rewardReasons"])
        self.family.apply(reward_call)
        wishes = [{"title": "一起拼图", "amount": 8}]
        self.family.apply(command("set_wish_suggestions", wishSuggestions=wishes,
                                  expectedWishSuggestions=initial["wishSuggestions"]))
        revision = self.family.read()["revision"]
        self.family.apply(reward_call)
        self.assertEqual(self.family.read()["revision"], revision)
        self.add(20)
        self.family.apply(command("reward", childId=self.child, amount=2, reason="阅读打卡"))
        before = self.family.read()["garden"]
        self.assertEqual(before["rewardReasons"], ["阅读打卡", "运动"])
        self.assertEqual(before["wishSuggestions"], wishes)
        self.family.apply(command("set_wish_suggestions", wishSuggestions=[], expectedWishSuggestions=wishes))
        after = self.family.read()["garden"]
        self.assertEqual(after["wishSuggestions"], [])
        self.assertEqual(after["entries"], before["entries"])
        self.assertEqual(after["children"], before["children"])
        with TemporaryFamily() as other:
            self.assertEqual(other.read()["garden"]["rewardReasons"], initial["rewardReasons"])

    def test_invalid_or_stale_suggestions_do_not_overwrite_settings(self):
        initial = self.family.read()
        old = initial["garden"]
        invalid = [command("set_reward_reasons", rewardReasons=reasons,
                           expectedRewardReasons=old["rewardReasons"])
                   for reasons in [None, {}, [""], ["a", " a "], [1], ["x" * 81], [str(i) for i in range(21)]]]
        invalid += [command("set_wish_suggestions", wishSuggestions=wishes,
                            expectedWishSuggestions=old["wishSuggestions"])
                    for wishes in [[{"title": "动画", "amount": n}] for n in [0, -1, 1000000, 1.5, "5"]]
                    + [[{"title": "动画"}], [{"title": " ", "amount": 5}],
                       [{"title": "动画", "amount": 5}, {"title": " 动画 ", "amount": 6}]]]
        for call in invalid:
            with self.assertRaises(psycopg.Error):
                self.family.apply(call)
        self.assertEqual(self.family.read()["garden"], old)
        self.assertEqual(self.family.read()["revision"], initial["revision"])
        self.family.apply(command("set_reward_reasons", rewardReasons=["阅读"],
                                  expectedRewardReasons=old["rewardReasons"]))
        with self.assertRaises(psycopg.Error) as error:
            self.family.apply(command("set_reward_reasons", rewardReasons=["运动"],
                                      expectedRewardReasons=old["rewardReasons"]))
        self.assertEqual(error.exception.sqlstate, "40001")
        self.assertEqual(self.family.read()["garden"]["rewardReasons"], ["阅读"])
        self.family.apply(command("set_wish_suggestions", wishSuggestions=[],
                                  expectedWishSuggestions=old["wishSuggestions"]))
        with self.assertRaises(psycopg.Error) as error:
            self.family.apply(command("set_wish_suggestions", wishSuggestions=old["wishSuggestions"],
                                      expectedWishSuggestions=old["wishSuggestions"]))
        self.assertEqual(error.exception.sqlstate, "40001")
        self.assertEqual(self.family.read()["garden"]["wishSuggestions"], [])

    def test_concurrent_rewards_are_added(self):
        self.add()
        calls = [command("reward", childId=self.child, amount=n, reason="并发奖励") for n in [1, 2]]
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            list(pool.map(self.family.apply, calls))
        data = self.family.read()["garden"]
        self.assertEqual(data["children"][0]["balance"], 13)
        self.assertEqual(len(data["entries"]), 3)

    def test_concurrent_redemption_cannot_overdraw(self):
        self.add(5)
        calls = [command("exchange", childId=self.child, amount=4, reason="并发兑换") for _ in range(2)]
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(self.family.apply, call) for call in calls]
            successes = 0
            for future in futures:
                try:
                    future.result()
                    successes += 1
                except psycopg.Error as error:
                    self.assertEqual(error.sqlstate, "P0001")
        self.assertEqual(successes, 1)
        data = self.family.read()["garden"]
        self.assertEqual(data["children"][0]["balance"], 1)
        self.assertEqual(len(data["entries"]), 2)

    def test_same_command_is_applied_once_even_concurrently(self):
        self.add()
        call = command("reward", childId=self.child, amount=2, reason="丢失响应后重试")
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            list(pool.map(self.family.apply, [call, call]))
        data = self.family.read()["garden"]
        self.assertEqual(data["children"][0]["balance"], 12)
        self.assertEqual(len(data["entries"]), 2)
        changed = copy.deepcopy(call)
        changed["payload"]["amount"] = 8
        with self.assertRaises(psycopg.Error):
            self.family.apply(changed)
        self.assertEqual(self.family.read()["garden"]["children"][0]["balance"], 12)

    def test_failed_transaction_does_not_change_state(self):
        self.add(999999)
        before = self.family.read()
        for call in [command("reward", childId=self.child, amount=1, reason="溢出"),
                     command("exchange", childId=self.child, amount=-1, reason="非法数量"),
                     command("reward", childId=self.child, amount=1, reason=" ")]:
            with self.assertRaises(psycopg.Error):
                self.family.apply(call)
        after = self.family.read()
        self.assertEqual(before["garden"], after["garden"])
        self.assertEqual(before["revision"], after["revision"])

    def test_stale_profile_edit_preserves_rewards_and_rejects_balance_reset(self):
        self.add()
        self.family.apply(command("reward", childId=self.child, amount=2, reason="另一台设备奖励"))
        self.family.apply(command("update_child", childId=self.child, name="新昵称", avatar=4,
                                  balance=None, expectedBalance=10))
        self.assertEqual(self.family.read()["garden"]["children"][0]["balance"], 12)
        with self.assertRaises(psycopg.Error) as error:
            self.family.apply(command("update_child", childId=self.child, name="新昵称", avatar=4,
                                      balance=5, expectedBalance=10))
        self.assertEqual(error.exception.sqlstate, "40001")
        self.assertEqual(self.family.read()["garden"]["children"][0]["balance"], 12)

    def test_app_role_cannot_edit_tables_read_other_family_or_call_helpers(self):
        self.add()
        for query in ["SELECT * FROM red_flowers.children", "UPDATE red_flowers.children SET balance=999",
                      "SELECT red_flowers._snapshot('00000000-0000-0000-0000-000000000000')"]:
            with self.family.connect() as db:
                with self.assertRaises(psycopg.Error) as error:
                    db.execute(query)
                self.assertEqual(error.exception.sqlstate, "42501")
        with TemporaryFamily() as other:
            other_child = str(uuid4())
            other.apply(command("add_child", childId=other_child, name="其他家庭", avatar=1, balance=50))
            with self.assertRaises(psycopg.Error):
                self.family.apply(command("reward", childId=other_child, amount=2, reason="越权"))
            self.assertEqual(other.read()["garden"]["children"][0]["balance"], 50)

    def local_data(self):
        return {"version": 1, "selectedChildId": self.child,
                "children": [{"id": self.child, "name": "旧版本小朋友", "avatar": 1,
                              "balance": 8, "createdAt": "2026-10-06T01:00:00Z"}],
                "entries": [{"id": "legacy-initial", "childId": self.child, "kind": "initial",
                             "amount": 10, "balanceAfter": 10, "reason": "初始",
                             "createdAt": "2026-10-06T01:00:00Z"},
                            {"id": "legacy-exchange", "childId": self.child, "kind": "exchange",
                             "amount": -2, "balanceAfter": 8, "reason": "旧版兑换",
                             "createdAt": "2026-10-06T02:00:00Z"}]}

    def test_local_import_is_atomic_preserves_history_and_does_not_reset_cloud(self):
        local = self.local_data()
        self.family.apply(command("import_local", garden=local))
        self.family.apply(command("reward", childId=self.child, amount=3, reason="云端新奖励"))
        self.family.apply(command("import_local", garden=local))
        data = self.family.read()["garden"]
        self.assertEqual(data["children"][0]["balance"], 11)
        self.assertEqual([e["amount"] for e in data["entries"]], [10, -2, 3])
        self.assertEqual(data["entries"][1]["reason"], "旧版兑换")

    def test_corrupt_import_rolls_back_profiles_and_ledger(self):
        local = self.local_data()
        local["entries"][1]["balanceAfter"] = 999
        with self.assertRaises(psycopg.Error):
            self.family.apply(command("import_local", garden=local))
        self.assertEqual(self.family.read()["garden"]["children"], [])
        self.assertEqual(self.family.read()["garden"]["entries"], [])
        local = self.local_data()
        local["entries"].append(copy.deepcopy(local["entries"][0]))
        with self.assertRaises(psycopg.Error):
            self.family.apply(command("import_local", garden=local))
        self.assertEqual(self.family.read()["garden"]["children"], [])


if __name__ == "__main__":
    unittest.main()
