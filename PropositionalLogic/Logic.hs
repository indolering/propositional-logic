{- |
Module      :  $Header$
Description :  The propositional formula and the operations on it.
Copyright   :  (c) Till Theis
License     :  MIT

Maintainer  :  Till Theis <theis.till@gmail.com>
Stability   :  experimental
Portability :  portable

This is the main module which implements the propositional 'Formula' type
itself and all the algorithms on it.

-}


module PropositionalLogic.Logic where

import Prelude hiding (foldr1)
import Data.Foldable (foldr1)
import qualified Data.Set as Set
import qualified Data.Map as Map
import Data.Maybe (fromJust)
import Data.List (nub, elemIndices, delete)
import Data.Function (on)


-- | Propositional formulae in any form are represented by the atomic formulae
-- 'T' (true), 'F' (false) and 'Symbol' and by nesting those within the basic
-- logical connectives.
--
-- Each formula has its form type @t@ attached, i.e. whether its a formula in the
-- negative normal form ('NNF') or any of the available formula types.
data Formula t = T                                   -- ^ Atom (true)
               | F                                   -- ^ Atom (false)
               | Symbol String                       -- ^ Atom
               | Negation (Formula t)                -- ^ Unary connective
               -- (sometimes treated as atom, sometimes as connective)
               | Conjunction (Formula t) (Formula t) -- ^ Connective
               | Disjunction (Formula t) (Formula t) -- ^ Connective
               | Implication (Formula t) (Formula t) -- ^ Connective
               | Equivalence (Formula t) (Formula t) -- ^ Connective
               deriving (Show, Ord)



-- * Types

-- | Default 'Formula' form type. Formulae of this type don't have any structure
-- constraints.
data Fancy  = Fancy deriving Show

-- | 'Formula'e in the 'Normal' form don't include 'Implication's or
-- 'Equivalence's as those connectives can be created from the other ones.
data Normal = Normal deriving Show

-- | The negative normal form is similiar to the 'Normal' 'Formula' type but
-- only allows 'Negation's on atoms.
data NNF    = NNF deriving Show

-- | The connective normal form extends the negative normal form in that
-- 'Disjunction's must not contain any 'Conjunction's.
data CNF    = CNF deriving Show

-- | The disjunctive normal form extends the negative normal form in that
-- 'Conjunction's must not contain any 'Disjunction's.
data DNF    = DNF deriving Show



-- * Equality

instance Eq (Formula t) where
    x == y = truthTable x == truthTable y


-- | Mapping from the 'Symbol's of a 'Formula' to the boolean values they
-- represent.
type SymbolMapping = Map.Map String Bool

-- | Mapping from unique combinations of 'SymbolMapping's to the boolean value
-- the related 'Formula' yields with each configuration.
type TruthTable = Map.Map SymbolMapping Bool


-- | The truth table (<http://en.wikipedia.org/wiki/Truth_table>) of the
-- 'Formula'.
truthTable :: Formula t -> TruthTable
truthTable x = foldr insert Map.empty . mappings $ Set.toList $ symbols x
    where insert :: SymbolMapping -> TruthTable -> TruthTable
          insert k = Map.insert k (eval k x)

          -- | Generate the 'SymbolMapping' from the given 'Symbol's and
          -- 'Formula'.
          mappings :: [String] -> [SymbolMapping]
          mappings = map (foldr Map.union Map.empty) . mappingMaps

          -- | From a list of 'Symbol's generate a list of lists where each
          -- inner one contains a Map, holding exactly one symbol with its
          -- assigned boolean value. The union of the maps of a sublist will
          -- describe the complete 'SymbolMapping' for that partcular row
          -- in the truth table.
          mappingMaps :: [String] -> [[SymbolMapping]]
          mappingMaps syms = map (zipWith Map.singleton syms) $ combos syms

          -- | The list of distinct value combinations for each symbol. The
          -- values still need to be combined with the actual 'Symbol' strings.
          combos :: [String] -> [[Bool]]
          combos syms = cartProd . take (length syms) $ repeat [True, False]


-- | The cartesian product of the elements of the list.
--
-- >>> cartProd [[1,2], [8,9]]
-- [[1,8],[1,9],[2,8],[2,9]]
cartProd :: [[a]] -> [[a]]
cartProd [] = []
cartProd [[]] = [[]]
cartProd [xs] = [ [x] | x <- xs ]
cartProd (xs:xss) = [ x:ys | x <- xs, ys <- cartProd xss ]


-- | Extract all symbol names from the 'Formula'.
--
-- >>> symbols $ Symbol "Y" `Conjunction` Negation (Symbol "X")
-- fromList ["X","Y"]
symbols :: Formula t -> Set.Set String
symbols = foldFormula insert Set.empty
    where insert (Symbol s) syms = Set.insert s syms
          insert _ syms = syms


-- | Evaluate the 'Formula' with its corresponding symbol-to-boolean-mapping
-- to its truth value.
eval :: SymbolMapping -> Formula t -> Bool
eval mapping = toBool . deepTransform reduce
    where reduce T = T
          reduce F = F
          reduce (Symbol s) = fromBool . fromJust $ Map.lookup s mapping
          reduce (Negation T) = F
          reduce (Negation F) = T
          reduce val@(Conjunction _ _) = fromBool $ reconnectMap (&&) toBool val
          reduce val@(Disjunction _ _) = fromBool $ reconnectMap (||) toBool val
          reduce val@(Implication _ _) = fromBool . eval mapping $ mkNormalVal val
          reduce val@(Equivalence _ _) = fromBool . eval mapping $ mkNormalVal val
          reduce _ = error "Logic.eval.reduce: Impossible"

          fromBool True = T
          fromBool False = F
          toBool T = True
          toBool F = False



-- * Type Casts

-- | /Unsave(!)/ cast a 'Formula' from any type to any other type.
-- Formulae are casted regardless of their actual values.
--
-- Bad example (remember the definition of 'Normal' which says that 'Normal'
-- 'Formulae' must not include 'Implication's):
--
-- >>> :t cast (T `Implication` T) :: Formula Normal
-- cast (T `Implication` T) :: Formula Normal :: Formula Normal
cast :: Formula t -> Formula u
cast = transform cast

-- | Cast any 'Formula' to a 'Fancy' 'Formula'. This is safe because 'Fancy'
-- allows all kinds of sub-'Formula'e.
fancy :: Formula t -> Formula Fancy
fancy = cast

-- | Cast any 'Formula' to a 'Normal' 'Formula'. The caller must ensure that
-- the given 'Formula' doesn't include sub-'Formula'e of incompatible types
-- (i.e. 'Fancy' with 'Implication's or 'Equivalence's).
normal :: Formula t -> Formula Normal
normal = cast

-- | Cast any 'Formula' to a 'NNF' 'Formula'. The caller must ensure that
-- the given 'Formula' doesn't include sub-'Formula'e of incompatible types.
nnf :: Formula t -> Formula NNF
nnf = cast

-- | Cast any 'Formula' to a 'CNF' 'Formula'. The caller must ensure that
-- the given 'Formula' doesn't include sub-'Formula'e of incompatible types.
cnf :: Formula t -> Formula CNF
cnf = cast

-- | Cast any 'Formula' to a 'DNF' 'Formula'. The caller must ensure that
-- the given 'Formula' doesn't include sub-'Formula'e of incompatible types.
dnf :: Formula t -> Formula DNF
dnf = cast



-- * Transformations

-- | Transform a 'Formula' by applying a function to the arguments of its
-- outer connective. Atoms will not be transformed.
--
-- Example:
--
-- > transform Negation (Conjunction T F) == Conjunction (Negation T) (Negation F)
transform :: (Formula t -> Formula u) -> Formula t -> Formula u
transform _ T = T
transform _ F = F
transform _ (Symbol s) = Symbol s
transform f (Negation x) = Negation $ f x
transform f (Conjunction x y) = Conjunction (f x) (f y)
transform f (Disjunction x y) = Disjunction (f x) (f y)
transform f (Implication x y) = Implication (f x) (f y)
transform f (Equivalence x y) = Equivalence (f x) (f y)


-- | Recursively 'transform' a 'Formula', beginning at the atoms. While the
-- normal 'transform' function only transforms the connective's arguments,
-- 'deepTransform' does also transform the connective itself.
deepTransform :: (Formula t -> Formula t) -> Formula t -> Formula t
deepTransform f x = f (transform (deepTransform f) x)


-- | Reduce a 'Formula' to a single value, beginning at the atoms. The order in
-- which the connective's arguments are traversed and combined is undefined.
foldFormula :: (Formula t -> a -> a) -> a -> Formula t -> a
foldFormula f z T = f T z
foldFormula f z F = f F z
foldFormula f z val@(Symbol _) = f val z
foldFormula f z val@(Negation x) = f val z'
    where z' = foldFormula f z x
foldFormula f z val@(Conjunction x y) = foldConnective f z x y val
foldFormula f z val@(Disjunction x y) = foldConnective f z x y val
foldFormula f z val@(Implication x y) = foldConnective f z x y val
foldFormula f z val@(Equivalence x y) = foldConnective f z x y val

foldConnective f z x y val = f val z''
    where z'  = foldFormula f z y
          z'' = foldFormula f z' x


-- | Change a 'Formula''s connective. The connective can be substituted with
-- another 'Formula' constructor or an arbitrary binary function. Note that
-- this function is only defined for binary connectives!
reconnect :: (Formula t -> Formula t -> a) -> Formula t -> a
reconnect f (Conjunction x y) = f x y
reconnect f (Disjunction x y) = f x y
reconnect f (Implication x y) = f x y
reconnect f (Equivalence x y) = f x y
reconnect _ _ = undefined



-- * Normal Forms

-- | Convert a 'Fancy' 'Formula' to 'Formula' in the 'Normal' form. All
-- 'Formula'e, except the 'Fancy' ones, are already in the 'Normal' form.
mkNormal :: Formula Fancy -> Formula Normal
mkNormal = normal . deepTransform mkNormalVal

-- | Translate 'Fancy' 'Formula' constructors to their 'Normal' equivalents.
-- This is a \'flat\' function and is meant to be used with 'deepTransform'.
mkNormalVal :: Formula t -> Formula t
mkNormalVal (Implication x y) = Negation x `Disjunction` y
mkNormalVal (Equivalence x y) =
    transform mkNormalVal $ Implication x y `Conjunction` Implication y x
mkNormalVal x = x



-- | Convert a 'Normal' 'Formula' to 'Formula' in the negative normal form. All
-- 'Formula'e, except the 'Fancy' and 'Normal' ones, are already in the 'NNF'
-- form.
mkNNF :: Formula Normal -> Formula NNF
mkNNF = nnf . deepTransform doubleNegation . deepTransform deMorgan


-- | Remove 'Negation's in front of connectives by moving the 'Negation' into
-- the connective (for more information please refer to
-- <http://en.wikipedia.org/wiki/De_Morgan%27s_laws>).
-- This is a \'flat\' function and is meant to be used with 'deepTransform'.
deMorgan :: Formula t -> Formula t
deMorgan (Negation (Conjunction x y)) =
    transform deMorgan $ Negation x `Disjunction` Negation y
deMorgan (Negation (Disjunction x y)) =
    transform deMorgan $ Negation x `Conjunction` Negation y
deMorgan x = x


-- | Remove double 'Negation's as they neutralize themselves.
-- This is a \'flat\' function and is meant to be used with 'deepTransform'.
doubleNegation :: Formula t -> Formula t
doubleNegation (Negation (Negation x)) = x
doubleNegation x = x



-- | Convert a 'Formula' in the negative normal form to a 'Formula' in the
-- conjunctive normal form.
mkCNF :: Formula NNF -> Formula CNF
mkCNF = cnf . deepTransform mkCNFVal

-- | Ensure that no 'Disjunction' contains any 'Conjunction's by making use of
-- the distributive law (<http://en.wikipedia.org/wiki/Distributivity>).
-- This is a \'flat\' function and is meant to be used with 'deepTransform'.
mkCNFVal :: Formula t -> Formula t
mkCNFVal (Disjunction x@(Conjunction _ _) y) =
    transform (mkCNFVal . Disjunction y) x
mkCNFVal (Disjunction y x@(Conjunction _ _)) = mkCNFVal $ Disjunction x y
mkCNFVal x = x



-- | Convert a 'Formula' in the negative normal form to a 'Formula' in the
-- disjunctive normal form.
mkDNF :: Formula NNF -> Formula DNF
mkDNF = dnf . deepTransform mkDNFVal

-- | Ensure that no 'Conjunction' contains any 'Disjunction's by making use of
-- the distributive law (<http://en.wikipedia.org/wiki/Distributivity>).
-- This is a \'flat\' function and is meant to be used with 'deepTransform'.
mkDNFVal :: Formula t -> Formula t
mkDNFVal (Conjunction x@(Disjunction _ _) y) =
    transform (mkDNFVal . Conjunction y) x
mkDNFVal (Conjunction y x@(Disjunction _ _)) = mkDNFVal $ Conjunction x y
mkDNFVal x = x



-- * Simplification

-- | Find all the 'SymbolMapping's in a 'TruthTable' for which the Formula
-- returns true (the models).
trueMappings :: TruthTable -> [SymbolMapping]
trueMappings = Map.keys . Map.filter id

-- | Convert a 'TruthTable' to a matching 'Formula'.
toFormula :: TruthTable -> Formula DNF
toFormula = outerFold . trueMappings
    where outerFold :: [SymbolMapping] -> Formula DNF
          outerFold = foldr1 Disjunction . map innerFold
          innerFold :: SymbolMapping -> Formula DNF
          innerFold = foldr1 Conjunction . map toAtom . Map.toList
          toAtom :: (String, Bool) -> Formula DNF
          toAtom (s, True) = Symbol s
          toAtom (s, False) = Negation $ Symbol s

-- | First 'transform' and then 'reconnect' a 'Formula' but don't require the
-- transformer to yield 'Formula' results.
reconnectMap :: (a -> a -> b) -> (Formula t -> a) -> Formula t -> b
reconnectMap fc fm x = fc (fm $ fst p) (fm $ snd p)
    where p = reconnect (,) x


-- | Apply the function @f@ to the argument @x@ if the condition @cond@ holds.
-- Leave @x@ unchanged otherwise.
alterIf :: Bool -> (a -> a) -> a -> a
alterIf cond f x = if cond then f x else x



-- | Value representation for the Quine-McCluskey algorithm.
data QMVal = QMTrue | QMFalse | QMDontCare deriving (Show, Eq)

toQMVal :: Bool -> QMVal
toQMVal True = QMTrue
toQMVal False = QMFalse

qmMappings :: [SymbolMapping] -> [[QMVal]]
qmMappings = map (map toQMVal . Map.elems)

-- | Quine–McCluskey algorithm
-- (<http://en.wikipedia.org/wiki/Quine%E2%80%93McCluskey_algorithm>,
-- <http://www.eetimes.com/discussion/programmer-s-toolbox/4025004/All-about-Quine-McClusky>)
-- to minimize a given 'Formula'.
--qm :: Formula t -> Formula t
qm x = let todo = qmMappings . trueMappings $ truthTable x
       in qm' [] todo todo []

qm' :: [[QMVal]] -- ^ values we are done with and relevant
    -> [[QMVal]] -- ^ values we still have to work with
    -> [[QMVal]] -- ^ values which have not been merged yet
    -> [[QMVal]] -- ^ values for next round
    -> [[QMVal]] -- ^ all the relevant values
qm' done [] unmerged [] = nub $ done ++ unmerged
qm' done [] unmerged next = qm' (done ++ unmerged) next next []
qm' done (x:xs) unmerged next = qm' done' xs unmerged' next'
    where mergeable = filter (\y -> isComparable x y && diff x y == 1) xs
          done'     = alterIf (null mergeable && x `elem` unmerged) (x:) done
          unmerged' = alterIf (not $ null mergeable) (filter (`notElem` x:mergeable)) unmerged
          next'     = next ++ map (merge x) mergeable

          merge        = zipWith (\a b -> if a == b then a else QMDontCare)
          diff x y     = length . filter not $ zipWith (==) x y
          isComparable = (==) `on` elemIndices QMDontCare