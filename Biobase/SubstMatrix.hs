
module Biobase.SubstMatrix where

import           Control.DeepSeq (NFData(..))
import           Control.Lens
import           Control.Monad.Except
import           Control.Monad.IO.Class
import           Data.Aeson (FromJSON,ToJSON)
import           Data.Binary (Binary)
import           Data.List (maximumBy,find)
import           Data.Serialize (Serialize)
import           Data.Vector.Unboxed.Deriving
import           GHC.Generics (Generic)
import           Numeric.Log
import qualified Data.Map.Strict as M
import qualified Data.Vector.Unboxed as VU
import           System.Directory (doesFileExist)
import           System.Exit (exitSuccess)
import           Text.Printf

import           Biobase.GeneticCodes.Translation
import           Biobase.GeneticCodes.Types
import           Biobase.Primary.AA (aaRange)
import           Biobase.Primary.Letter
import           Biobase.Primary.Nuc.DNA ()
import           Biobase.Primary.Trans
import           Biobase.Types.BioSequence (DNA,AA)
import           Biobase.Types.Codon
import           Data.PrimitiveArray as PA
import           Numeric.Discretized
import qualified Biobase.Primary.AA as AA
import qualified Biobase.Primary.Nuc.DNA as DNA
import           StatisticalMechanics.Ensemble
import           Statistics.Odds
import           Statistics.Probability

import           Biobase.SubstMatrix.Embedded
import           Biobase.SubstMatrix.Import
import           Biobase.SubstMatrix.Types



-- | The usual substitution matrix, but here with a codon and an amino acid
-- to be compared.
--
-- The resulting @AA@ are tagged with the name type from the @DNA n@.
--
-- TODO Definitely use the correct upper bound constants here!

mkANuc3SubstMat
  ∷ TranslationTable (Letter DNA n) (Letter AA n)
  → AASubstMat t (DiscLogOdds k) n
  → ANuc3SubstMat t (Letter AA n, (DiscLogOdds k)) n n
mkANuc3SubstMat tbl (AASubstMat m)
  = ANuc3SubstMat
  $ fromAssocs (ZZ:..LtLetter AA.Undef:..LtLetter DNA.N:..LtLetter DNA.N:..LtLetter DNA.N) (AA.Undef, DiscLogOdds . Discretized $ -999)
    [ ( (Z:.a:.u:.v:.w)
      , (t, m!(Z:.a:.t))
      )
    | a <- VU.toList aaRange
    , u <- [DNA.A .. DNA.N], v <- [DNA.A .. DNA.N], w <- [DNA.A .. DNA.N]
    , let b = Codon u v w
    , let t = translate tbl b
    ]

-- | This function does the following:
-- 1. check if @fname@ is a file, and if so try to load it.
-- 2. if not, check if @fname@ happens to be the name of one of the known @PAM/BLOSUM@ tables.

fromFileOrCached ∷ (MonadIO m, MonadError String m) ⇒ FilePath → m (AASubstMat t (DiscLogOdds Unknown) a)
fromFileOrCached fname = do
  dfe ← liftIO $ doesFileExist fname
  if | fname == "list" → do
        mapM_ (liftIO . printf "%s\n" . fst) embeddedPamBlosum
        liftIO exitSuccess
     | dfe → fromFile fname
     | Just (k,v) ← find ((fname==).fst) embeddedPamBlosum → return v
     | otherwise → throwError $ fname ++ " is neither a file nor a known substitution matrix"

-- | Turn log-odds into log-probabilities. Normalizes over the whole set of
-- values in the matrix.

mkProbabilityMatrix
  ∷ Double
  → AASubstMat t (DiscLogOdds k) n
  → AASubstMat t (Log (Probability NotNormalized Double)) n
mkProbabilityMatrix invScale (AASubstMat dlo) = AASubstMat $ PA.map (/nrm) $ dbl
  where dbl = PA.map (\(DiscLogOdds (Discretized k)) → stateLogProbability (negate invScale) $ fromIntegral @Int @Double k) dlo
        nrm = maximum . Prelude.map snd $ PA.assocs dbl



{-
-- | Create a 2-tuple to amino acid substitution matrix. Here, @f@ combines
-- all to entries that have the same 2-tuple index.

mkANuc2SubstMat
  ∷ ((Z:.Letter AA:.Letter DNA:.Letter DNA) → (Letter AA, DiscLogOdds) → (Letter AA, DiscLogOdds) → Ordering)
  → AASubstMat t DiscLogOdds
  → ANuc2SubstMat t (Letter AA, DiscLogOdds)
mkANuc2SubstMat f (AASubstMat m)
  = ANuc2SubstMat
  $ fromAssocs (ZZ:..LtLetter (length aaRange):..LtLetter 5:..LtLetter 5) (AA.Undef, DiscLogOdds $ -999)
  . M.assocs
  . M.mapWithKey (\k → maximumBy (f k))
  . M.fromListWith (++)
  $ [ ((Z:.a:.x:.y), [maybe (AA.Undef, DiscLogOdds $ -999) (\k -> (k, m!(Z:.a:.k))) $ M.lookup uvw dnaAAmap])
    | a <- aaRange
    , u <- [DNA.A .. DNA.N], v <- [DNA.A .. DNA.N], w <- [DNA.A .. DNA.N]
    , (x,y) <- [ (u,v), (u,w), (v,w) ]
    , let uvw = VU.fromList [u,v,w]
    ]

-- | The most degenerate case, where just a single nucleotide remains in
-- the amino-acid / nucleotide substitution. Again, @f@ combines different
-- entries.

mkANuc1SubstMat
  ∷ ((Z:.Letter AA:.Letter DNA) → (Letter AA, DiscLogOdds) → (Letter AA, DiscLogOdds) → Ordering)
  → AASubstMat t DiscLogOdds
  → ANuc1SubstMat t (Letter AA, DiscLogOdds)
mkANuc1SubstMat f (AASubstMat m)
  = ANuc1SubstMat
  $ fromAssocs (ZZ:..LtLetter (length aaRange):..LtLetter 5) (AA.Undef, DiscLogOdds $ -999)
  . M.assocs
  . M.mapWithKey (\k → maximumBy (f k))
  . M.fromListWith (++)
  $ [ ((Z:.a:.x), [maybe (AA.Undef, DiscLogOdds $ -999) (\k -> (k, m!(Z:.a:.k))) $ M.lookup uvw dnaAAmap])
    | a <- aaRange
    , u <- [DNA.A .. DNA.N], v <- [DNA.A .. DNA.N], w <- [DNA.A .. DNA.N]
    , x <- [u,v,w]
    , let uvw = VU.fromList [u,v,w]
    ]
-}

