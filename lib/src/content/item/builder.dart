import 'package:malison/malison.dart';

import '../../engine.dart';
import '../action/condition.dart';
import '../action/detection.dart';
import '../action/eat.dart';
import '../action/flow.dart';
import '../action/heal.dart';
import '../action/illuminate.dart';
import '../action/mapping.dart';
import '../action/ray.dart';
import '../skill/skills.dart';
import 'affixes.dart';
import 'items.dart';

int _sortIndex = 0;
_CategoryBuilder _category;
_ItemBuilder _item;
String _affixTag;
_AffixBuilder _affix;

_CategoryBuilder category(int glyph, {String verb, int stack}) {
  finishItem();

  _category = _CategoryBuilder();
  _category._glyph = glyph;
  _category._verb = verb;
  _category._maxStack = stack;

  return _category;
}

_ItemBuilder item(String name, int depth, double frequency, Color color) {
  finishItem();

  _item = _ItemBuilder();
  _item._name = name;
  _item._depth = depth;
  _item._frequency = frequency;
  _item._color = color;

  return _item;
}

void affixCategory(String tag) {
  finishAffix();
  _affixTag = tag;
}

_AffixBuilder affix(String name, int depth, double frequency) {
  finishAffix();

  bool isPrefix;
  if (name.endsWith(" _")) {
    name = name.substring(0, name.length - 2);
    isPrefix = true;
  } else if (name.startsWith("_ ")) {
    name = name.substring(2);
    isPrefix = false;
  } else {
    throw 'Affix "$name" must start or end with "_".';
  }

  return _affix = _AffixBuilder(name, isPrefix, depth, frequency);
}

class _BaseBuilder {
  final List<Skill> _skills = [];
  final Map<Element, int> _destroyChance = {};

  int _maxStack;
  Element _tossElement;
  int _tossDamage;
  int _tossRange;
  TossItemUse _tossUse;
  int _emanation;
  int _fuel;

  /// Percent chance of objects in the current category breaking when thrown.
  int _breakage;

  void stack(int stack) {
    _maxStack = stack;
  }

  /// Makes items in the category throwable.
  void toss({int damage, Element element, int range, int breakage}) {
    _tossDamage = damage;
    _tossElement = element;
    _tossRange = range;
    _breakage = breakage;
  }

  void tossUse(TossItemUse use) {
    _tossUse = use;
  }

  void destroy(Element element, {int chance, int fuel}) {
    _destroyChance[element] = chance;
    // TODO: Per-element fuel.
    _fuel = fuel;
  }

  void skill(String skill) {
    _skills.add(Skills.find(skill));
  }

  void skills(List<String> skills) {
    _skills.addAll(skills.map(Skills.find));
  }
}

class _CategoryBuilder extends _BaseBuilder {
  /// The current glyph's character code. Any items defined will use this.
  int _glyph;

  String _equipSlot;

  String _weaponType;
  String _tag;
  String _verb;

  void tag(String tagPath) {
    // Define the tag path and store the leaf tag which is what gets used by
    // the item types.
    Items.types.defineTags("item/$tagPath");
    var tags = tagPath.split("/");
    _tag = tags.last;

    const tagEquipSlots = [
      'weapon',
      'ring',
      'necklace',
      'body',
      'cloak',
      'shield',
      'helm',
      'gloves',
      'boots'
    ];

    for (var equipSlot in tagEquipSlots) {
      if (tags.contains(equipSlot)) {
        _equipSlot = equipSlot;
        break;
      }
    }

    if (tags.contains("weapon")) {
      _weaponType = tags[tags.indexOf("weapon") + 1];
    }

    // TODO: Hacky. We need a matching tag hiearchy for affixes so that, for
    // example, a "sword" item will match a "weapon" affix.
    Affixes.defineItemTag(tagPath);
  }
}

class _ItemBuilder extends _BaseBuilder {
  // category too.
  Color _color;
  double _frequency;
  ItemUse _use;
  Attack _attack;
  int _weight;
  int _heft;
  int _armor;

  String _name;
  int _depth;

  void armor(int armor, {int weight}) {
    _armor = armor;
    _weight = weight;
  }

  void weapon(int damage, {int heft, Element element}) {
    _attack = Attack(null, _category._verb, damage, null, element);
    _heft = heft;
  }

  void ranged(String noun, {int heft, int damage, int range}) {
    _attack = Attack(Noun(noun), "pierce[s]", damage, range);
    // TODO: Make this per-item once it does something.
    _heft = heft;
  }

  void use(ItemUse use) {
    _use = use;
  }

  void food(int amount) {
    use(() => EatAction(amount));
  }

  void detection(List<DetectType> types, {int range}) {
    use(() => DetectAction(types, range));
  }

  void resistSalve(Element element) {
    use(() => ResistAction(40, element));
  }

  void mapping(int distance, {bool illuminate}) {
    use(() => MappingAction(distance, illuminate: illuminate));
  }

  // TODO: Take list of conditions to cure?
  void heal(int amount, {bool curePoison = false}) {
    use(() => HealAction(amount, curePoison: curePoison));
  }

  /// Sets a use and toss use that creates an expanding ring of elemental
  /// damage.
  void ball(Element element, String noun, String verb, int damage,
      {int range}) {
    var attack = Attack(Noun(noun), verb, damage, range ?? 3, element);

    use(() => RingSelfAction(attack));
    tossUse((pos) => RingFromAction(attack, pos));
  }

  /// Sets a use and toss use that creates a flow of elemental damage.
  void flow(Element element, String noun, String verb, int damage,
      {int range = 5, bool fly = false}) {
    var attack = Attack(Noun(noun), verb, damage, range, element);

    var motilities = MotilitySet([Motility.walk]);
    if (fly) motilities += Motility.fly;

    use(() => FlowSelfAction(attack, motilities));
    tossUse((pos) => FlowFromAction(attack, pos, motilities));
  }

  void lightSource({int level, int range}) {
    _emanation = level;

    if (range != null) use(() => IlluminateSelfAction(range, level + 1));
  }
}

class _AffixBuilder {
  final String _name;
  final bool _isPrefix;
  final int _depth;
  final double _frequency;

  double _heftScale;
  int _weightBonus;
  int _strikeBonus;
  double _damageScale;
  int _damageBonus;
  Element _brand;
  int _armor;

  final Map<Element, int> _resists = {};

  _AffixBuilder(this._name, this._isPrefix, this._depth, this._frequency);

  void heft(double scale) {
    _heftScale = scale;
  }

  void weight(int bonus) {
    _weightBonus = bonus;
  }

  void strike(int bonus) {
    _strikeBonus = bonus;
  }

  void damage({double scale, int bonus}) {
    _damageScale = scale;
    _damageBonus = bonus;
  }

  void brand(Element element, {int resist}) {
    _brand = element;

    // By default, branding also grants resistance.
    _resists[element] = resist ?? 1;
  }

  void armor(int armor) {
    _armor = armor;
  }

  void resist(Element element, [int power]) {
    _resists[element] = power ?? 1;
  }
}

void finishItem() {
  if (_item == null) return;

  var appearance = Glyph.fromCharCode(_category._glyph, _item._color);

  Toss toss;
  var tossDamage = _item._tossDamage ?? _category._tossDamage;
  if (tossDamage != null) {
    var noun = Noun("the ${_item._name.toLowerCase()}");
    var verb = "hits";
    if (_category._verb != null) {
      verb = Log.conjugate(_category._verb, Pronoun.it);
    }

    var range = _item._tossRange ?? _category._tossRange;
    assert(range != null);
    var element = _item._tossElement ?? _category._tossElement ?? Element.none;
    var use = _item._tossUse ?? _category._tossUse;
    var breakage = _category._breakage ?? _item._breakage ?? 0;

    var tossAttack = Attack(noun, verb, tossDamage, range, element);
    toss = Toss(breakage, tossAttack, use);
  }

  var itemType = ItemType(
      _item._name,
      appearance,
      _item._depth,
      _sortIndex++,
      _category._equipSlot,
      _category._weaponType,
      _item._use,
      _item._attack,
      toss,
      _item._armor ?? 0,
      0,
      _item._maxStack ?? _category._maxStack ?? 1,
      weight: _item._weight ?? 0,
      heft: _item._heft ?? 0,
      emanation: _item._emanation ?? _category._emanation,
      fuel: _item._fuel ?? _category._fuel);

  itemType.destroyChance.addAll(_category._destroyChance);
  itemType.destroyChance.addAll(_item._destroyChance);

  itemType.skills.addAll(_category._skills);
  itemType.skills.addAll(_item._skills);

  Items.types.add(itemType.name, itemType, itemType.depth, _item._frequency,
      _category._tag);

  _item = null;
}

void finishAffix() {
  if (_affix == null) return;

  var affix = Affix(_affix._name,
      heftScale: _affix._heftScale,
      weightBonus: _affix._weightBonus,
      strikeBonus: _affix._strikeBonus,
      damageScale: _affix._damageScale,
      damageBonus: _affix._damageBonus,
      brand: _affix._brand,
      armor: _affix._armor);

  _affix._resists.forEach(affix.resist);

  (_affix._isPrefix ? Affixes.prefixes : Affixes.suffixes)
      .add(_affix._name, affix, _affix._depth, _affix._frequency, _affixTag);
  _affix = null;
}
