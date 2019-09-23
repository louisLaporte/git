#!/bin/sh

test_description='pre-commit and pre-merge-commit hooks'

. ./test-lib.sh

HOOKDIR="$(git rev-parse --git-dir)/hooks"
PRECOMMIT="$HOOKDIR/pre-commit"
PRECOMMIT_DIR="$HOOKDIR/pre-commit.d"
PREMERGE="$HOOKDIR/pre-merge-commit"

# Prepare sample scripts that write their $0 to actual_hooks
test_expect_success 'sample script setup' '
	mkdir -p "$HOOKDIR" &&
	write_script "$HOOKDIR/success.sample" <<-\EOF &&
	echo $0 >>actual_hooks
	exit 0
	EOF
	write_script "$HOOKDIR/fail.sample" <<-\EOF &&
	echo $0 >>actual_hooks
	exit 1
	EOF
	write_script "$HOOKDIR/non-exec.sample" <<-\EOF &&
	echo $0 >>actual_hooks
	exit 1
	EOF
	chmod -x "$HOOKDIR/non-exec.sample" &&
	write_script "$HOOKDIR/require-prefix.sample" <<-\EOF &&
	echo $0 >>actual_hooks
	test $GIT_PREFIX = "success/"
	EOF
	write_script "$HOOKDIR/check-author.sample" <<-\EOF
	echo $0 >>actual_hooks
	test "$GIT_AUTHOR_NAME" = "New Author" &&
	test "$GIT_AUTHOR_EMAIL" = "newauthor@example.com"
	EOF
'

test_expect_success 'pre-commit scripts setup' '
	mkdir $PRECOMMIT_DIR &&
	write_script "$PRECOMMIT_DIR/check_commit" <<-\EOF &&
	#!/bin/sh
	test -z "$(git diff --cached --check)"
	EOF
	write_script "$PRECOMMIT_DIR/run_container_linter_ok" <<-\EOF &&
	#!/bin/sh
	echo "run_container_linter_ok"
	EOF
	write_script "$PRECOMMIT_DIR/run_container_linter_fail" <<-\EOF &&
	#!/bin/sh
	echo "run_container_linter_fail"
	exit 1
	EOF
	write_script "$PRECOMMIT_DIR/main_fail" <<-\EOF &&
	#!/bin/sh
	PRECOMMIT_DIR="$(pwd)/.git/hooks/pre-commit.d"
	"$PRECOMMIT_DIR/check_commit"
	"$PRECOMMIT_DIR/run_container_linter_fail"
	EOF
	write_script "$PRECOMMIT_DIR/main_ok" <<-\EOF
	#!/bin/sh
	PRECOMMIT_DIR="$(pwd)/.git/hooks/pre-commit.d"
	"$PRECOMMIT_DIR/check_commit"
	"$PRECOMMIT_DIR/run_container_linter_ok"
	EOF
'

test_expect_success 'root commit' '
	echo "root" >file &&
	git add file &&
	git commit -m "zeroth" &&
	git checkout -b side &&
	echo "foo" >foo &&
	git add foo &&
	git commit -m "make it non-ff" &&
	git branch side-orig side &&
	git checkout master
'

test_expect_success 'setup conflicting branches' '
	test_when_finished "git checkout master" &&
	git checkout -b conflicting-a master &&
	echo a >conflicting &&
	git add conflicting &&
	git commit -m conflicting-a &&
	git checkout -b conflicting-b master &&
	echo b >conflicting &&
	git add conflicting &&
	git commit -m conflicting-b
'

test_expect_success 'with no hook' '
	test_when_finished "rm -f actual_hooks" &&
	echo "foo" >file &&
	git add file &&
	git commit -m "first" &&
	test_path_is_missing actual_hooks
'

test_expect_success 'with no hook (merge)' '
	test_when_finished "rm -f actual_hooks" &&
	git branch -f side side-orig &&
	git checkout side &&
	git merge -m "merge master" master &&
	git checkout master &&
	test_path_is_missing actual_hooks
'

test_expect_success '--no-verify with no hook' '
	test_when_finished "rm -f actual_hooks" &&
	echo "bar" >file &&
	git add file &&
	git commit --no-verify -m "bar" &&
	test_path_is_missing actual_hooks
'

test_expect_success '--no-verify with no hook (merge)' '
	test_when_finished "rm -f actual_hooks" &&
	git branch -f side side-orig &&
	git checkout side &&
	git merge --no-verify -m "merge master" master &&
	git checkout master &&
	test_path_is_missing actual_hooks
'

test_expect_success 'with succeeding hook' '
	test_when_finished "rm -f \"$PRECOMMIT\" expected_hooks actual_hooks" &&
	cp "$HOOKDIR/success.sample" "$PRECOMMIT" &&
	echo "$PRECOMMIT" >expected_hooks &&
	echo "more" >>file &&
	git add file &&
	git commit -m "more" &&
	test_cmp expected_hooks actual_hooks
'

test_expect_success 'with succeeding hook (merge)' '
	test_when_finished "rm -f \"$PREMERGE\" expected_hooks actual_hooks" &&
	cp "$HOOKDIR/success.sample" "$PREMERGE" &&
	echo "$PREMERGE" >expected_hooks &&
	git checkout side &&
	git merge -m "merge master" master &&
	git checkout master &&
	test_cmp expected_hooks actual_hooks
'

test_expect_success 'automatic merge fails; both hooks are available' '
	test_when_finished "rm -f \"$PREMERGE\" \"$PRECOMMIT\"" &&
	test_when_finished "rm -f expected_hooks actual_hooks" &&
	test_when_finished "git checkout master" &&
	cp "$HOOKDIR/success.sample" "$PREMERGE" &&
	cp "$HOOKDIR/success.sample" "$PRECOMMIT" &&

	git checkout conflicting-a &&
	test_must_fail git merge -m "merge conflicting-b" conflicting-b &&
	test_path_is_missing actual_hooks &&

	echo "$PRECOMMIT" >expected_hooks &&
	echo a+b >conflicting &&
	git add conflicting &&
	git commit -m "resolve conflict" &&
	test_cmp expected_hooks actual_hooks
'

test_expect_success '--no-verify with succeeding hook' '
	test_when_finished "rm -f \"$PRECOMMIT\" actual_hooks" &&
	cp "$HOOKDIR/success.sample" "$PRECOMMIT" &&
	echo "even more" >>file &&
	git add file &&
	git commit --no-verify -m "even more" &&
	test_path_is_missing actual_hooks
'

test_expect_success '--no-verify with succeeding hook (merge)' '
	test_when_finished "rm -f \"$PREMERGE\" actual_hooks" &&
	cp "$HOOKDIR/success.sample" "$PREMERGE" &&
	git branch -f side side-orig &&
	git checkout side &&
	git merge --no-verify -m "merge master" master &&
	git checkout master &&
	test_path_is_missing actual_hooks
'

test_expect_success 'with failing hook' '
	test_when_finished "rm -f \"$PRECOMMIT\" expected_hooks actual_hooks" &&
	cp "$HOOKDIR/fail.sample" "$PRECOMMIT" &&
	echo "$PRECOMMIT" >expected_hooks &&
	echo "another" >>file &&
	git add file &&
	test_must_fail git commit -m "another" &&
	test_cmp expected_hooks actual_hooks
'

test_expect_success '--no-verify with failing hook' '
	test_when_finished "rm -f \"$PRECOMMIT\" actual_hooks" &&
	cp "$HOOKDIR/fail.sample" "$PRECOMMIT" &&
	echo "stuff" >>file &&
	git add file &&
	git commit --no-verify -m "stuff" &&
	test_path_is_missing actual_hooks
'

test_expect_success 'with failing hook (merge)' '
	test_when_finished "rm -f \"$PREMERGE\" expected_hooks actual_hooks" &&
	cp "$HOOKDIR/fail.sample" "$PREMERGE" &&
	echo "$PREMERGE" >expected_hooks &&
	git checkout side &&
	test_must_fail git merge -m "merge master" master &&
	git checkout master &&
	test_cmp expected_hooks actual_hooks
'

test_expect_success '--no-verify with failing hook (merge)' '
	test_when_finished "rm -f \"$PREMERGE\" actual_hooks" &&
	cp "$HOOKDIR/fail.sample" "$PREMERGE" &&
	git branch -f side side-orig &&
	git checkout side &&
	git merge --no-verify -m "merge master" master &&
	git checkout master &&
	test_path_is_missing actual_hooks
'

test_expect_success POSIXPERM 'with non-executable hook' '
	test_when_finished "rm -f \"$PRECOMMIT\" actual_hooks" &&
	cp "$HOOKDIR/non-exec.sample" "$PRECOMMIT" &&
	echo "content" >>file &&
	git add file &&
	git commit -m "content" &&
	test_path_is_missing actual_hooks
'

test_expect_success POSIXPERM '--no-verify with non-executable hook' '
	test_when_finished "rm -f \"$PRECOMMIT\" actual_hooks" &&
	cp "$HOOKDIR/non-exec.sample" "$PRECOMMIT" &&
	echo "more content" >>file &&
	git add file &&
	git commit --no-verify -m "more content" &&
	test_path_is_missing actual_hooks
'

test_expect_success POSIXPERM 'with non-executable hook (merge)' '
	test_when_finished "rm -f \"$PREMERGE\" actual_hooks" &&
	cp "$HOOKDIR/non-exec.sample" "$PREMERGE" &&
	git branch -f side side-orig &&
	git checkout side &&
	git merge -m "merge master" master &&
	git checkout master &&
	test_path_is_missing actual_hooks
'

test_expect_success POSIXPERM '--no-verify with non-executable hook (merge)' '
	test_when_finished "rm -f \"$PREMERGE\" actual_hooks" &&
	cp "$HOOKDIR/non-exec.sample" "$PREMERGE" &&
	git branch -f side side-orig &&
	git checkout side &&
	git merge --no-verify -m "merge master" master &&
	git checkout master &&
	test_path_is_missing actual_hooks
'

test_expect_success 'with hook requiring GIT_PREFIX' '
	test_when_finished "rm -rf \"$PRECOMMIT\" expected_hooks actual_hooks success" &&
	cp "$HOOKDIR/require-prefix.sample" "$PRECOMMIT" &&
	echo "$PRECOMMIT" >expected_hooks &&
	echo "more content" >>file &&
	git add file &&
	mkdir success &&
	(
		cd success &&
		git commit -m "hook requires GIT_PREFIX = success/"
	) &&
	test_cmp expected_hooks actual_hooks
'

test_expect_success 'with failing hook requiring GIT_PREFIX' '
	test_when_finished "rm -rf \"$PRECOMMIT\" expected_hooks actual_hooks fail" &&
	cp "$HOOKDIR/require-prefix.sample" "$PRECOMMIT" &&
	echo "$PRECOMMIT" >expected_hooks &&
	echo "more content" >>file &&
	git add file &&
	mkdir fail &&
	(
		cd fail &&
		test_must_fail git commit -m "hook must fail"
	) &&
	git checkout -- file &&
	test_cmp expected_hooks actual_hooks
'

test_expect_success 'check the author in hook' '
	test_when_finished "rm -f \"$PRECOMMIT\" expected_hooks actual_hooks" &&
	cp "$HOOKDIR/check-author.sample" "$PRECOMMIT" &&
	cat >expected_hooks <<-EOF &&
	$PRECOMMIT
	$PRECOMMIT
	$PRECOMMIT
	EOF
	test_must_fail git commit --allow-empty -m "by a.u.thor" &&
	(
		GIT_AUTHOR_NAME="New Author" &&
		GIT_AUTHOR_EMAIL="newauthor@example.com" &&
		export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL &&
		git commit --allow-empty -m "by new.author via env" &&
		git show -s
	) &&
	git commit --author="New Author <newauthor@example.com>" \
		--allow-empty -m "by new.author via command line" &&
	git show -s &&
	test_cmp expected_hooks actual_hooks
'

test_expect_success 'with succeding specified pre-commit hooks' '
	echo "foo" >file &&
	git add file &&
	git commit -m "bar" --pre-commit=main_ok file
'

test_expect_success 'with failing specified pre-commit hooks' '
	echo "foo" >>file &&
	git add file &&
	test_must_fail git commit -m "bar" --pre-commit=main_fail file
'

test_expect_success 'with failing specified pre-commit hooks from hooksPath' '
	cp -r .git/hooks .git/custom-hooks &&
	mv .git/custom-hooks/pre-commit.d/main_fail \
		.git/custom-hooks/main_custom_fail &&
	git config core.hooksPath .git/custom-hooks &&
	echo "foo" >>file &&
	git add file &&
	test_must_fail git commit -m "bar" --pre-commit=main_custom_fail file &&
	git config --unset core.hooksPath
'

test_expect_success 'with failing specified pre-commit hook and --no-verify' '
	echo "foo" >>file &&
	git add file &&
	test_must_fail git commit -m "bar" --no-verify \
		--pre-commit=run_container_linter_ok file 2>stderr &&
	grep "fatal: incompatible option --no-verify and --pre-commit" stderr
'

test_done
