#import "ApolloBotSuspicionViewController.h"
#import "ApolloBotSuspicion.h"
#import "ApolloState.h"
#import "UserDefaultConstants.h"

@interface ApolloBotSuspicionViewController ()
@property(nonatomic) NSInteger sampleAge;
@property(nonatomic) NSInteger samplePostKarma;
@property(nonatomic) NSInteger sampleCommentKarma;
@property(nonatomic) NSInteger inputMinimum;
@property(nonatomic) NSInteger inputMaximum;
@property(nonatomic, weak) UIAlertAction *inputSaveAction;
@end

static BOOL ApolloBotParseInteger(NSString *text, NSInteger minimum, NSInteger maximum, NSInteger *value) {
    NSString *input = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSScanner *scanner = [NSScanner scannerWithString:input ?: @""];
    long long number = 0;
    if (!input.length || ![scanner scanLongLong:&number] || !scanner.isAtEnd || number < minimum || number > maximum) return NO;
    if (value) *value = (NSInteger)number;
    return YES;
}

@implementation ApolloBotSuspicionViewController

- (instancetype)initWithStyle:(UITableViewStyle)style {
    self = [super initWithStyle:style];
    if (self) {
        _sampleAge = 180;
        _samplePostKarma = 10000;
        _sampleCommentKarma = 1000;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Bot Suspicion";
    if (self.navigationController.viewControllers.firstObject == self) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeSettings)];
    }
}

- (void)closeSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)validateNumberInput:(UITextField *)field {
    self.inputSaveAction.enabled = ApolloBotParseInteger(field.text, self.inputMinimum, self.inputMaximum, NULL);
}

- (void)editNumberWithTitle:(NSString *)title value:(NSInteger)value
                    minimum:(NSInteger)minimum maximum:(NSInteger)maximum
                      apply:(void (^)(NSInteger))apply {
    NSString *message = [NSString stringWithFormat:@"Enter a whole number from %ld to %ld.", (long)minimum, (long)maximum];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
        preferredStyle:UIAlertControllerStyleAlert];
    self.inputMinimum = minimum;
    self.inputMaximum = maximum;
    __weak typeof(self) weakSelf = self;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.keyboardType = minimum < 0 ? UIKeyboardTypeNumbersAndPunctuation : UIKeyboardTypeNumberPad;
        field.text = [NSString stringWithFormat:@"%ld", (long)value];
        field.accessibilityLabel = title;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        [field addTarget:weakSelf action:@selector(validateNumberInput:) forControlEvents:UIControlEventEditingChanged];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert = alert;
    UIAlertAction *save = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSInteger number = 0;
        if (ApolloBotParseInteger(weakAlert.textFields.firstObject.text, minimum, maximum, &number)) apply(number);
    }];
    self.inputSaveAction = save;
    [alert addAction:save];
    [self validateNumberInput:alert.textFields.firstObject];
    [self presentViewController:alert animated:YES completion:nil];
}

- (ApolloSettingsRow *)numberRow:(NSString *)rowID title:(NSString *)title
                         minimum:(NSInteger)minimum maximum:(NSInteger)maximum
                           value:(NSInteger (^)(void))value apply:(void (^)(NSInteger))apply {
    __weak typeof(self) weakSelf = self;
    ApolloSettingsRow *row = [ApolloSettingsRow valueRowWithID:rowID title:title detail:^NSString * {
        return [NSNumberFormatter localizedStringFromNumber:@(value()) numberStyle:NSNumberFormatterDecimalStyle];
    } onSelect:^{
        [weakSelf editNumberWithTitle:title value:value() minimum:minimum maximum:maximum apply:^(NSInteger number) {
            apply(number);
            [weakSelf reloadRowWithID:rowID];
            [weakSelf reloadRowWithID:@"bot.preview"];
        }];
    }];
    row.configure = ^(UITableViewCell *cell) { cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; };
    return row;
}

- (ApolloSettingsRow *)ruleRow:(NSString *)rowID title:(NSString *)title key:(NSString *)key
                      minimum:(NSInteger)minimum maximum:(NSInteger)maximum {
    return [self numberRow:rowID title:title minimum:minimum maximum:maximum value:^NSInteger {
        return [NSUserDefaults.standardUserDefaults integerForKey:key];
    } apply:^(NSInteger number) {
        [NSUserDefaults.standardUserDefaults setInteger:number forKey:key];
        ApolloBotSuspicionSettingsDidChange();
    }];
}

- (ApolloSettingsRow *)toggleRow:(NSString *)rowID title:(NSString *)title key:(NSString *)key {
    return [ApolloSettingsRow switchRowWithID:rowID title:title isOn:^BOOL {
        return [NSUserDefaults.standardUserDefaults boolForKey:key];
    } onToggle:^(UISwitch *sender) {
        [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:key];
        ApolloBotSuspicionSettingsDidChange();
    }];
}

- (NSArray<ApolloSettingsSection *> *)buildForm {
    __weak typeof(self) weakSelf = self;
    ApolloSettingsRow *preview = [ApolloSettingsRow customRowWithID:@"bot.preview" cell:^UITableViewCell *(UITableView *table, __unused ApolloSettingsRow *row) {
        UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"BotPreview"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"BotPreview"];
        ApolloBotSuspicionViewController *vc = weakSelf;
        ApolloBotScore score = ApolloBotEvaluate(sBotSuspicionRules, vc.sampleAge, vc.samplePostKarma, vc.sampleCommentKarma);
        cell.textLabel.text = ApolloBotScoreExplanation(score, sBotSuspicionRules, vc.sampleAge);
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        cell.textLabel.adjustsFontForContentSizeCategory = YES;
        [vc apollo_applyPrimaryTextColorToCell:cell];
        return cell;
    } onSelect:nil];
    ApolloSettingsRow *sampleAge = [self numberRow:@"bot.sampleAge" title:@"Example Account Age (Days)" minimum:0 maximum:36500
        value:^NSInteger { return weakSelf.sampleAge; } apply:^(NSInteger value) { weakSelf.sampleAge = value; }];
    ApolloSettingsRow *samplePosts = [self numberRow:@"bot.samplePosts" title:@"Example Post Karma" minimum:-1000000000 maximum:1000000000
        value:^NSInteger { return weakSelf.samplePostKarma; } apply:^(NSInteger value) { weakSelf.samplePostKarma = value; }];
    ApolloSettingsRow *sampleComments = [self numberRow:@"bot.sampleComments" title:@"Example Comment Karma" minimum:-1000000000 maximum:1000000000
        value:^NSInteger { return weakSelf.sampleCommentKarma; } apply:^(NSInteger value) { weakSelf.sampleCommentKarma = value; }];
    ApolloSettingsRow *reset = [ApolloSettingsRow buttonRowWithID:@"bot.reset" title:@"Reset Rules to Defaults" action:^{
        NSDictionary *defaults = ApolloBotSuspicionDefaults();
        for (NSString *key in defaults) {
            // Reset the algorithm only; leave the user's display choices alone.
            if ([key isEqualToString:UDKeyBotSuspicionEnabled] || [key isEqualToString:UDKeyBotSuspicionPosts]
                || [key isEqualToString:UDKeyBotSuspicionComments]) continue;
            [NSUserDefaults.standardUserDefaults setObject:defaults[key] forKey:key];
        }
        ApolloBotSuspicionSettingsDidChange();
        [weakSelf rebuildForm];
    }];
    return @[
        [ApolloSettingsSection sectionWithTitle:@"Labels" footer:
            @"Adds a tappable Possible bot label to posts and comments whose author meets your rules. "
             "This is an account heuristic, not a judgment about the content. Nothing is hidden or blocked. "
             "Unknown profiles stay unlabelled."
            rows:@[
                [self toggleRow:@"bot.enabled" title:@"Enable Bot Suspicion" key:UDKeyBotSuspicionEnabled],
                [self toggleRow:@"bot.posts" title:@"Show on Posts" key:UDKeyBotSuspicionPosts],
                [self toggleRow:@"bot.comments" title:@"Show on Comments" key:UDKeyBotSuspicionComments],
                [self ruleRow:@"bot.threshold" title:@"Score Needed for Label" key:UDKeyBotSuspicionThreshold minimum:1 maximum:100],
            ]],
        [ApolloSettingsSection sectionWithTitle:@"Young Account" footer:@"Adds points when the account is younger than this many days. Set points to 0 to disable this rule."
            rows:@[
                [self ruleRow:@"bot.age" title:@"Age Under (Days)" key:UDKeyBotSuspicionAgeDays minimum:1 maximum:36500],
                [self ruleRow:@"bot.ageWeight" title:@"Young Account Points" key:UDKeyBotSuspicionAgeWeight minimum:0 maximum:100],
            ]],
        [ApolloSettingsSection sectionWithTitle:@"High Karma" footer:@"Uses post karma plus comment karma. Award karma is excluded."
            rows:@[
                [self ruleRow:@"bot.karma" title:@"Karma At Least" key:UDKeyBotSuspicionKarma minimum:1 maximum:1000000000],
                [self ruleRow:@"bot.karmaWeight" title:@"High Karma Points" key:UDKeyBotSuspicionKarmaWeight minimum:0 maximum:100],
            ]],
        [ApolloSettingsSection sectionWithTitle:@"Karma per Day" footer:
            @"Total karma divided by account age, with a minimum of one day. This is a lifetime average, not a measurement of recent activity."
            rows:@[
                [self ruleRow:@"bot.rate" title:@"Karma/Day At Least" key:UDKeyBotSuspicionKarmaPerDay minimum:1 maximum:10000000],
                [self ruleRow:@"bot.rateWeight" title:@"Karma/Day Points" key:UDKeyBotSuspicionRateWeight minimum:0 maximum:100],
            ]],
        [ApolloSettingsSection sectionWithTitle:@"Try the Algorithm" footer:
            @"Change these example values or any rule above to see the score immediately, even while labels are disabled. Example values are not saved."
            rows:@[sampleAge, samplePosts, sampleComments, preview]],
        [ApolloSettingsSection sectionWithTitle:nil footer:
            @"Uses Reddit's public profile statistics, cached for up to 24 hours. Additional lookups run one at a time for visible authors. "
             "Scores stay on your device; no third-party detection service is used."
            rows:@[reset]],
    ];
}
@end
